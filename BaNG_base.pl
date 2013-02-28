sanityprogcheck("$global_settings->{RSYNC}");
sanityprogcheck("$global_settings->{BTRFS}");

sub sanityprogcheck {
    my ($prog) = @_;

    if ( ! -x "$prog"){
        print "$prog not found!\n";
        logit($host_source,"INTERNAL", "$prog not found");
        exit 0;
    }
    else {
        return 1;
    }
}

sub get_report_header {
    my $starttime  = `date`;
    my $startstamp = `date +%s`;
    print STDERR <<"EOF";

* * * Backup report * * *
      Version: $version
----------------------------------------------------
Start Time: $starttime
----------------------------------------------------
EOF
#Backing up:  ${SRCHOST}${SRCPART}
#        to:  `hostname`:$BKDIR/$BKFOLDER
#Exclude-File: $EXCLUDEFROM
#last backup: $LASTMSG
#----------------------------------------------------
}
