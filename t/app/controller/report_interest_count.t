use strict;
use warnings;
use Test::More;

use FixMyStreet::TestMech;
use Web::Scraper;
use Path::Class;
use DateTime;

my $mech = FixMyStreet::TestMech->new;

# create a test user and report
$mech->delete_user('test@example.com');
my $user =
  FixMyStreet::App->model('DB::User')
  ->find_or_create( { email => 'test@example.com', name => 'Test User' } );
ok $user, "created test user";

my $user2 =
  FixMyStreet::App->model('DB::User')
  ->find_or_create( { email => 'test2@example.com', name => 'Other User' } );
ok $user2, "created test user";

my $dt = DateTime->new(
    year   => 2011,
    month  => 04,
    day    => 16,
    hour   => 15,
    minute => 47,
    second => 23
);

my $report = FixMyStreet::App->model('DB::Problem')->find_or_create(
    {
        postcode           => 'SW1A 1AA',
        council            => '2504',
        areas              => ',105255,11806,11828,2247,2504,',
        category           => 'Other',
        title              => 'Test 2',
        detail             => 'Test 2 Detail',
        used_map           => 't',
        name               => 'Test User',
        anonymous          => 'f',
        state              => 'confirmed',
        confirmed          => $dt->ymd . ' ' . $dt->hms,
        lang               => 'en-gb',
        service            => '',
        cobrand            => 'default',
        cobrand_data       => '',
        send_questionnaire => 't',
        latitude           => '51.5016605453401',
        longitude          => '-0.142497580865087',
        user_id            => $user->id,
    }
);
my $report_id = $report->id;
ok $report, "created test report - $report_id";

SKIP: {
    skip( "Need 'fixmybarangay' in ALLOWED_COBRANDS config", 29 )
        unless FixMyStreet::Cobrand->exists('fixmybarangay');
    for my $test (
        {
            desc => 'if not from council then no supporter button',
            from_council => 0,
            support_string => 'No supporters',
        },
        {
            desc => 'from council user can increment supported count',
            from_council => 2504,
            support_string => 'No supporters',
            updated_support => '1 supporter'
        },
        {
            desc => 'correct grammar for more than one supporter',
            from_council => 2504,
            support_string => '1 supporter',
            updated_support => '2 supporters'
        },
    ) {
        subtest $test->{desc} => sub {
            ok $mech->host('fixmybarangay.com'), 'changed to fixmybarangay';
            $mech->log_in_ok( $user->email );
            $user->from_council( $test->{from_council} );
            $user->update;

            $report->discard_changes;
            $report->council( $test->{report_council} );
            $report->update;

            $mech->get_ok("/report/$report_id");
            $mech->content_contains( $test->{support_string} );

            if ( $test->{from_council} ) {
                $mech->content_contains('Add support');
                $mech->submit_form_ok( { form_number => 1 } );

                is $mech->uri, "http://fixmybarangay.com/report/$report_id", 'add support redirects to report page';

                $mech->content_contains($test->{updated_support});
            } else {
                $mech->content_lacks( 'Add support' );
            }
        };
    }

    subtest 'check non council user cannot increment support count' => sub {
        ok $mech->host('fixmybarangay.com'), 'changed to fixmybarangay';
        $report->discard_changes;
        $report->interest_count(1);
        ok $report->update(), 'updated interest count';

        $report->discard_changes;
        is $report->interest_count, 1, 'correct interest count';

        $mech->get_ok("/report/$report_id");
        $mech->content_contains( '1 supporter' );

        $mech->post_ok("/report/support", { id => $report_id } );

        is $mech->uri, "http://fixmybarangay.com/report/$report_id", 'add support redirects to report page';

        $mech->content_contains( '1 supporter' );
    };
};

subtest 'check support details not shown if not enabled in cobrand' => sub {
    ok $mech->host('fixmystreet.com'), 'changed to fixmystreet';

    $report->interest_count(1);
    ok $report->update, 'updated interest count';

    $mech->get_ok("/report/$report_id");
    $mech->content_lacks( '1 supporter' );
};

$report->discard_changes;
$report->council( 2504 );
$report->update;

# tidy up
$mech->delete_user('test@example.com');
done_testing();
