use strict;
use warnings;
use 5.010;
use Test::More;
use Cwd qw( abs_path );
use Date::Parse;
use File::Basename;
use lib dirname( abs_path($0) ) . "/../lib";
use BaNG::Wipe;

my %maxcount = (
    daily   => 3,
    weekly  => 4,
    monthly => 1,
);

my @patterns = qw(
    Keep_single_backup
        X
        d
    Keep_three_dailies
        XXX
        ddd
    Fourth_daily_becomes_weekly
        XXXX
        dddw
    Keep_oldest_of_two_weeklies
        XXXXX
        ddd/w
    Keep_weekly_if_bkp_is_missing
        XXX-X
        ddd-w
    Wipe_second_weekly_before_week_has_passed
        XXXX-----X
        ddd/-----w
    Keep_second_weekly_when_week_has_passed
        XXXX------X
        dddw------w
    Wipe_after_second_weekly
        XXXXX------X
        ddd/w------w
    Keep_second_weekly_after_week_has_passed
        XXXX-------X
        dddw-------w
    Keep_third_weekly
        XXXX------X------X
        dddw------w------w
    Wipe_before_month_has_passed
        XXXX-----X------X------X------X
        ddd/-----w------w------w------w
    Keep_monthly_when_month_has_passed
        XXXX------X------X------X------X
        dddw------w------w------w------m
    Wipe_after_month_has_passed
        XXXXX------X------X------X------X
        ddd/w------w------w------w------m
    Ignore_if_one_weekly_was_later
        XXXX-------X-----X------X------X
        dddw-------w-----w------w------m
    Ignore_if_one_weekly_was_earlier
        XXXX-----X-------X------X------X
        ddd/-----w-------w------w------m
    Wipe_before_taking_second_monthly
        XXXX-----X------X------X------X---------------------------X
        ddd/-----w------w------w------w---------------------------m
    Rotate_monthly_when_reaching_second_month
        XXXX------X------X------X------X---------------------------X
        dddw------w------w------w------m---------------------------/
    Keep_single_monthly
        XXXX------X------X------X------X-------------------------XX
        dddw------w------w------w------/-------------------------/m
    Wipe_what_lies_outside_of_range
        XXXX-----X------X------X------X---------------------------XXXXXXXXXXX------X
        ddd/-----w------w------w------w---------------------------m//////////------/
    Ignore_when_most_recent_backups_are_missing
        ----XXX------X------X------X------X---------------------------X
        ----ddd------w------w------w------w---------------------------m
);
#       [d][w----][w----][w----][w----][m-------------------------]
#       newest-----------------------------------------------oldest

test_all(@patterns);

# TODO write tests with multiple backups per day

done_testing();

# -- Helper functions --

sub test_all {
    my (@patterns) = @_;

    for ( my $idx=0; $idx<=$#patterns; $idx+=3 ) {
        my $title  = $patterns[$idx];
        my $input  = $patterns[$idx+1];
        my $answer = $patterns[$idx+2];
        unlike( test_pattern( $input, $answer), qr|WRONG|, $title );
    }

    return 1;
}

sub test_pattern {
    my ($input, $answer) = @_;

    my @available = dates_from_pattern($input);
    my %stack     = &BaNG::Wipe::_fill_stacks(\@available, \%maxcount);

    # show input and output
    my ($output, $report);
    my $i = 0;
    CHAR: foreach my $char ( split( '', $input ) ) {
        if ( $char ne 'X' ) {
            $output .= '-';
            next CHAR;
        }
        foreach my $type (qw( monthly weekly daily wipe )) {
            if ( $available[$i] ~~ @{$stack{$type}} ) {
                my $flag = (split( '', $type ))[0];
                $flag = '/' if $type eq 'wipe';
                $output .= $flag;
            }
        }
        $i++;
    }
    # warn if output is different from expected answer
    $output .= "\t WRONG, should be\n$answer" if $output ne $answer;
    $report .= "\n$input\n$output\n";

    return $report;
}

sub dates_from_pattern {
    my ($pattern) = @_;

    my @dates;
    my $epoch = str2time('2013.06.01');
    my @chars = split( '', $pattern );

    foreach my $char (@chars) {
        push( @dates, $epoch ) if ( $char eq 'X' );
        $epoch -= 24*3600;
    }

    return @dates;
}
