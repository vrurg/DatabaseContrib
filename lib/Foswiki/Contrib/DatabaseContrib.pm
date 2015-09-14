# See bottom of file for default license and copyright information
package Foswiki::Contrib::DatabaseContrib;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use DBI;

# use Error qw(:try);
use CGI qw(:html2);
use Carp qw(longmess);

my ( $initialized, %dbi_connections );

# $VERSION is referred to by Foswiki, and is the only global variable that
# *must* exist in this package. For best compatibility, the simple quoted decimal
# version '1.00' is preferred over the triplet form 'v1.0.0'.
# "1.23_001" for "alpha" versions which compares lower than '1.24'.

# For triplet format, The v prefix is required, along with "use version".
# These statements MUST be on the same line.
#  use version; our $VERSION = 'v1.2.3_001'
# See "perldoc version" for more information on version strings.
#
# Note:  Alpha versions compare as numerically lower than the non-alpha version
# so the versions in ascending order are:
#   v1.2.1_001 -> v1.2.2 -> v1.2.2_001 -> v1.2.3
#   1.21_001 -> 1.22 -> 1.22_001 -> 1.23
#
our $VERSION = '1.00';

# $RELEASE is used in the "Find More Extensions" automation in configure.
# It is a manually maintained string used to identify functionality steps.
# You can use any of the following formats:
# tuple   - a sequence of integers separated by . e.g. 1.2.3. The numbers
#           usually refer to major.minor.patch release or similar. You can
#           use as many numbers as you like e.g. '1' or '1.2.3.4.5'.
# isodate - a date in ISO8601 format e.g. 2009-08-07
# date    - a date in 1 Jun 2009 format. Three letter English month names only.
# Note: it's important that this string is exactly the same in the extension
# topic - if you use %$RELEASE% with BuildContrib this is done automatically.
# It is preferred to keep this compatible with $VERSION. At some future
# date, Foswiki will deprecate RELEASE and use the VERSION string.
#
our $RELEASE = '15 Sep 2015';

# One-line description of the module
our $SHORTDESCRIPTION =
  'Provides subroutines useful in writing plugins that access a SQL database.';

use Exporter;
our ( @ISA, @EXPORT );
@ISA = qw(Exporter);

@EXPORT = qw( db_connect db_disconnect db_connected db_allowed );

sub warning {
    return Foswiki::Func::writeWarning(@_);
}

sub init {

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 0.77 ) {
        warning("Version mismatch between DatabaseContrib.pm and Plugins.pm");
        return 0;
    }

    my $connections = $Foswiki::cfg{Extensions}{DatabaseContrib}{connections};
    unless ($connections) {
        warning "No connections defined.";
        return 0;
    }
    %dbi_connections = %$connections;

    # Contrib correctly initialized
    return 1;
}

sub failure {
    my $msg = shift;
    if ($Foswiki::cfg{Contrib}{DatabaseContrib}{dieOnFailure}) {
        die $msg;
    }
    else {
        return 1;
    }
}

sub db_connected {
    unless ($initialized) {
        init;
        $initialized = 1;
    }

    my ($conname) = @_;

    return ( defined $dbi_connections{$conname} ) ? 1 : 0;
}

sub db_set_codepage {
    my $conname    = shift;
    my $connection = $dbi_connections{$conname};
    if ( $connection->{codepage} ) {

        # SETTING CODEPAGE $connection->{codepage} for $conname\n";
        if ( $connection->{driver} =~ /^(mysql|Pg)$/ ) {
            $connection->{dbh}->do("SET NAMES $connection->{codepage}");
            if ( $connection->{driver} eq 'mysql' ) {
                $connection->{dbh}
                  ->do("SET CHARACTER SET $connection->{codepage}");
            }
        }
    }
}

sub find_allowed {
    my $allow = shift;

    my $curUser = Foswiki::Func::getWikiUserName();
    my $found   = 0;
    my $allowed;
    foreach my $entity (@$allow) {
        $allowed = $entity;

        # Checking for access of $curUser within $entity
        if ( Foswiki::Func::isGroup($entity) ) {

            # $entity is a group
            $found =
              Foswiki::Func::isGroupMember( $entity, $curUser,
                { expand => 1 } );
        }
        else {
            # FIXME Potentially incorrect approach within Foswiki API.
            $entity =
              Foswiki::Func::userToWikiName(
                Foswiki::Func::wikiToUserName($entity), 0 );
            $found = ( $curUser eq $entity );
        }
        last if $found;
    }
    return $allowed if $found;
    return;
}

sub db_allowed {
    my ( $conname, $section ) = @_;
    my $connection = $dbi_connections{$conname};

    $section = "default"
      unless defined( $connection->{allow_do} )
      && defined( $connection->{allow_do}{$section} );
    my $allow =
         defined( $connection->{allow_do} )
      && defined( $connection->{allow_do}{$section} )
      && ref( $connection->{allow_do}{$section} ) eq 'ARRAY'
      ? $connection->{allow_do}{$section}
      : [];
    my $allowed = find_allowed($allow);
    return defined $allowed;
}

sub db_connect {
    unless ($initialized) {
        init;
        $initialized = 1;
    }

    my $conname         = shift;
    my $connection      = $dbi_connections{$conname};
    my @required_fields = qw(database driver);

    unless ( defined $connection->{dsn} ) {
        foreach my $field (@required_fields) {
            unless ( defined $connection->{$field} ) {
                return
                  if failure
"Required field $field is not defined for database connection $conname.\n";
            }
        }
    }

    my ( $dbuser, $dbpass ) =
      ( $connection->{user} || "", $connection->{password} || "" );

    if ( defined( $connection->{usermap} ) ) {
        my @maps =
          sort { ( $a =~ /Group$/ ) <=> ( $b =~ /Group$/ ) }
          keys %{ $connection->{usermap} };

        my $allowed = find_allowed( \@maps );
        if ($allowed) {
            $dbuser = $connection->{usermap}{$allowed}{user};
            $dbpass = $connection->{usermap}{$allowed}{password};
        }
    }

    unless ($dbuser) {
        return if failure "User is not allowed to connect to database";
    }

# CONNECTING TO $conname, ", (defined $connection->{dbh} ? $connection->{dbh} : "*undef*"), ", ", (defined $dbi_connections{$conname}{dbh} ? $dbi_connections{$conname}{dbh} : "*undef*"), "\n";
    unless ( $connection->{dbh} ) {

        # CONNECTING TO $conname\n";
        my $dsn;
        if ( defined $connection->{dsn} ) {
            $dsn = $connection->{dsn};
        }
        else {
            my $server =
              $connection->{server} ? "server=$connection->{server};" : "";
            $dsn =
"dbi:$connection->{driver}\:${server}database=$connection->{database}";
            $dsn .= ";host=$connection->{host}" if $connection->{host};
        }

        my @drv_attrs;
        if ( defined $connection->{driver_attributes}
            && ref( $connection->{driver_attributes} ) eq 'HASH' )
        {
            @drv_attrs =
              map { $_ => $connection->{driver_attributes}{$_} }
              grep { !/^(?:RaiseError|PrintError|FetchHashKeyName)$/ }
              keys %{ $connection->{driver_attributes} };

        }
        my $dbh = DBI->connect(
            $dsn, $dbuser, $dbpass,
            {
                RaiseError       => 1,
                PrintError       => 1,
                FetchHashKeyName => NAME_lc => @drv_attrs,
                @_
            }
        );
        unless ( defined $dbh ) {

#	        throw Error::Simple("DBI connect error for connection $conname: $DBI::errstr");
            return;
        }
        $connection->{dbh} = $dbh;
    }

    db_set_codepage($conname);

    if ( defined $connection->{init} ) {
        $connection->{dbh}->do( $connection->{init} );
    }

    return $connection->{dbh};
}

sub db_disconnect {
    foreach my $conname ( keys %dbi_connections ) {
        if ( $dbi_connections{$conname}{dbh} ) {
            $dbi_connections{$conname}{dbh}->commit
              unless $dbi_connections{$conname}{dbh}{AutoCommit};
            $dbi_connections{$conname}{dbh}->disconnect;
            delete $dbi_connections{$conname}{dbh};
        }
    }
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2015 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
