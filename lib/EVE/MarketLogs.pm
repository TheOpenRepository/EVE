package EVE::MarketLogs;

# Provides an abstraction over the capture and analysis of EVE market data

use 5.008;
use strict;
use warnings;
use File::Spec       0.80 ();
use File::Remove     1.48 ();
use File::Find::Rule 0.32 ();
use Parse::CSV       1.00 ();
use EVE::DB               ();




######################################################################
# Constructor and Accessors

sub new {
	my $class = shift;
	my $self  = bless { @_ }, $class;

	# Check params
	unless ( $self->dir and -d $self->dir ) {
		die "Missing or invalid market log directory";
	}

	return $self;
}

sub dir {
	$_[0]->{dir};
}





######################################################################
# Main Methods

# Find market log files
sub files {
	File::Find::Rule->relative->file->name('*.txt')->in( $_[0]->dir );
}

# Delete all existing market log files
sub flush {
	my $self = shift;

	foreach my $file ( $self->files ) {
		my $path = File::Spec->catfile( $self->dir, $file );
		File::Remove::remove($path) or die "Failed to remove '$path'";
	}

	return 1;
}

# Parse a single file
sub parse {
	my $self = shift;
	my $file = shift;

	# Parse information from the file name
	my @parts     = split /-/, $file;
	my $region    = $parts[-3] or die "Failed to find region in '$file'";
	my $product   = $parts[-2] or die "Failed to find product in '$file'";
	my $timestamp = $parts[-1] or die "Failed to find timestamp in '$file'";
	$timestamp =~ s/\.txt$//;
	$timestamp =~ s/(\d\d)(\d\d)(\d\d)/$1:$2:$3/;
	$timestamp =~ s/\./-/g;

	# Create the parser
	my $path   = File::Spec->catfile( $self->dir, $file );
	my $parser = Parse::CSV->new(
		file   => $path,
		fields => 'auto',
	) or die "Failed to create parser for '$path'";

	EVE::DB->begin;
	eval {
		while ( my $hash = $parser->fetch ) {
			$hash->{issued} =~ s/\.000$//;
			$hash->{bid} = ($hash->{bid} eq 'True') ? 1 : 0;
			EVE::DB::Price->create(
				order_id   => $hash->{orderID},
				timestamp  => $timestamp,
				region_id  => $hash->{regionID},
				system_id  => $hash->{solarSystemID},
				station_id => $hash->{stationID},
				product    => $product,
				issued     => $hash->{issued},
				duration   => $hash->{duration},
				bid        => $hash->{bid},
				price      => $hash->{price},
				range      => $hash->{range},
				entered    => $hash->{volEntered},
				minimum    => $hash->{minVolume},
				remaining  => $hash->{volRemaining},
				type_id    => $hash->{typeID},
				jumps      => $hash->{jumps},
			);
		}
	};
	if ( $@ or $parser->errstr ) {
		EVE::DB->rollback;
		die "Failed to parse '$path': " . ($@ || $parser->errstr);
	}
	EVE::DB->commit;

	return 1;
}

sub parse_all {
	my $self = shift;

	foreach my $file ( $self->files ) {
		$self->parse($file);
	}

	return 1;
}

1;