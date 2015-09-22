use strict;

package DatabaseContribTests;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use strict;
use Foswiki;
use Foswiki::Func;
use File::Temp;
use Foswiki::Contrib::DatabaseContrib;

sub new {
    my $self = shift()->SUPER::new(@_);
    return $self;
}

#sub createGroup {
#    my ( $this, $groupName, $members ) = @_;
#    my $q = $this->{session}{request};
#
#    if (!defined($members)) {
#        $members = '';
#    } elsif (ref($memebers) eq 'ARRAY') {
#        $members = join(",", @$members);
#    }
#
#    my $params = {
#        TopicName     => ['WikiGroups'],
#        action        => ['addUserToGroup'],
#        create          => 1,
#        groupname       => $group,
#        username        => $members,
#    };
#
#    my $query = Unit::Request->new($params);
#
#    $query->path_info("/$this->{users_web}/$params->{TopicName}");
#
#    $this->createNewFoswikiSession( undef, $query );
#    $this->assert( $this->{session}
#          ->topicExists( $this->{test_web}, $Foswiki::cfg{WebPrefsTopicName} )
#    );
#
#    $this->{session}->net->setMailHandler( \&FoswikiFnTestCase::sentMail );
#    try {
#        $this->captureWithKey(
#            manage => \&Foswiki::UI::Manage::manage,
#            $this->{session}
#        );
#    }
#    catch Foswiki::OopsException with {
#        my $e = shift;
#        if ( $this->check_dependency('Foswiki,<,1.2') ) {
#            $this->assert_str_equals( "attention", $e->{template},
#                $e->stringify() );
#            $this->assert_str_equals( "thanks", $e->{def}, $e->stringify() );
#        }
#        else {
#            $this->assert_str_equals( "manage", $e->{template},
#                $e->stringify() );
#            $this->assert_str_equals( "thanks", $e->{def}, $e->stringify() );
#        }
#    }
#    catch Foswiki::AccessControlException with {
#        my $e = shift;
#        $this->assert( 0, $e->stringify );
#    }
#    catch Error::Simple with {
#        $this->assert( 0, shift->stringify() );
#    }
#    otherwise {
#        $this->assert( 0, "expected an oops redirect" );
#    };
#
#    # Reload caches
#    $this->createNewFoswikiSession( undef, $q );
#    $this->{session}->net->setMailHandler( \&FoswikiFnTestCase::sentMail );
#}

# Set up the test fixture
sub set_up {
    my $this = shift;

    $this->SUPER::set_up();

    $this->registerUser( 'JohnSmith', 'Jogn', 'Smith', 'webmaster@otoib.dp.ua' );
    $this->registerUser( 'ElvisPresley', 'Elvis', 'Presley', 'webmaster@otoib.dp.ua' );
    $this->registerUser( 'DummyGuest', 'Dummy', 'Guest', 'nobody@otoib.dp.ua' );
    $this->registerUser( 'MightyAdmin', 'Miky', 'Theadmin', 'daemon@otoib.dp.ua' );

    $this->assert( Foswiki::Func::addUserToGroup($this->{session}->{user}, 'AdminGroup', 0), 'Failed to create a new admin' );
    $this->assert( Foswiki::Func::addUserToGroup('JohnSmith', 'TestGroup', 1), 'Failed to create TestGroup' );
    $this->assert( Foswiki::Func::addUserToGroup('DummyGuest', 'DummyGroup', 1), 'Failed to create DummyGroup' );
    $this->assert( Foswiki::Func::addUserToGroup('ElvisPresley', 'AnywhereQueryingGroup', 1), 'Failed to create AnywhereQueryingGroup' );
    $this->assert( Foswiki::Func::addUserToGroup('MightyAdmin', 'AdminGroup', 0), 'Failed to create a new admin' );
    $this->assert( Foswiki::Func::addUserToGroup('ScumBag', 'AdminGroup', 0), 'Failed to create a new admin' );
}

sub tear_down {
    my $this = shift;
    $this->SUPER::tear_down();
}

sub loadExtraConfig {
    my $this = shift;

    $this->SUPER::loadExtraConfig;

    $Foswiki::cfg{Contrib}{DatabaseContrib}{dieOnFailure} = 0;
    $Foswiki::cfg{Extensions}{DatabaseContrib}{connections} = {
        message_board => {
            driver => 'Mock',
            database => 'smaple_db',
            codepage => 'utf8',
            user => 'unmapped_user',
            password => 'unmapped_password',
            driver_attributes => {
                sqline_unicode => 1,
            },
            allow_do => {
                default => [qw(AdminGroup)],
                "Sandbox.DoTestTopic" => [qw(TestGroup)],
                "Sandbox.DoDummyTopic" => [qw(DummyGroup)],
                "Sandbox.DoForSelected" => [qw(JohnSmith ScumBag)],
            },
            allow_query => {
                default => [qw(AnywhereQueryingGroup)],
                '%USERSWEB%.QSiteMessageBoard' => 'DummyGroup',
                'Sandbox.QDummyTopic' => [qw(DummyGroup)],
                'Sandbox.QTestTopic' => [qw(JohnSmith)],
                "$this->{test_web}.QSomeImaginableTopic" => [qw(TestGroup DummyGuest)],
            },
            usermap => {
                DummyGroup => {
                    user => 'dummy_map_user',
                    password => 'dummy_map_password',
                },
            },
            # host => 'localhost',
        },
    };
}

sub test_permissions
{
    my $this = shift;

    my %check_pairs = (
        valid => {
            allow_do => [
                [qw(ScumBag AnyWeb.AnyTopic), "Admins are allowed anywhere by default"],
                [qw(JohnSmith Sandbox.DoForSelected), "Individual user allowed for a topic"],
                [qw(DummyGuest Sandbox.DoDummyTopic), "A user belongs to an allowed group"],
            ],
            allow_query => [
                [qw(MightyAdmin AnyWeb.AnyTopic), "Admins are like gods: allowed anywhere by default in allow_do"],
                [qw(JohnSmith Sandbox.QTestTopic), "Inidividual user allowed for a topic"],
                ['DummyGuest', "$this->{test_web}.QSomeImaginableTopic", "Individual user defined together with a group for a topic"],
                ['JohnSmith', "$this->{test_web}.QSomeImaginableTopic", "User within a group defined together with a individual user for a topic"],
                [qw(JohnSmith Sandbox.DoForSelected), "Individual user defined in allow_do"],
                [qw(DummyGuest Sandbox.DoDummyTopic), "User within a group defined in allow_do"],
                [qw(ElvisPresley AnotherWeb.AnotherTopic), "The king yet not the god: cannot be do-ing but still may query anywhere"],
            ],
        },
        invalid => {
            allow_do => [
                [qw(DummyGuest AnyWeb.AnyTopic), "A user anywhere outside his allowed zone"],
                [qw(JohnSmith Sandbox.QTestTopic), "Allowed for query, not for do-ing"],
            ],
            allow_query => [
                ['DummyGuest', "$Foswiki::cfg{UsersWebName}.QSiteMessageBoard", "Variable expandsion for topic name is not supported"],
                ['JohnSmith', '%USERSWEB%.QSiteMessageBoard', "Individual user not allowed for a topic"],
            ],
        },
    );

    foreach my $bunch (qw(valid invalid)) {
        foreach my $access_type (qw(allow_do allow_query)) {
            foreach my $test_pair (@{$check_pairs{$bunch}{$access_type}}) {
                if ($bunch eq 'valid') {
                    $this->assert(
                        access_allowed('message_board', $test_pair->[1], $access_type, $test_pair->[0]),
                        "$bunch $access_type for $test_pair->[0] on $test_pair->[1]: " . $test_pair->[2],
                    );
                } else {
                    $this->assert(
                        !access_allowed('message_board', $test_pair->[1], $access_type, $test_pair->[0]),
                        "$bunch $access_type for $test_pair->[0] on $test_pair->[1]: " . $test_pair->[2],
                    );
                }
            }
        }
    }
    
}

sub test_connect
{
    my $this = shift;

    my $dbh;
    $this->assert_not_null(
        $dbh = db_connect( 'message_board' ),
        'Failed: connection to message_board DB',
    );

    $this->assert_null(
        $dbh = db_connect( 'non_existent' ),
        'Failed: connection to non_existent DB',
    );
}

1;
