use IPC::Open3;

#################################
# Sanity checks for programs
#
sanityprogcheck("$global_settings->{RSYNC}");
sanityprogcheck("$global_settings->{BTRFS}");

###########################
# do the work!
#
sub do_work {
    ($queue_typ, $queue_content, $conn_test) = @_;
    my ($work_host, $work_src) = ('') x 2;

    my $rsync_options = eval_rsync_options($work_host);
    my $work_dest     = "$settings{$work_host}->{BKP_TARGET_PATH}/$settings{$work_host}->{BKP_PREFIX}/$work_host/current";

    logit($work_host, $work_src, "rsync start");
    my $rsync_command = "$rsync $rsync_options $work_host$work_src $work_dest";

    print "Do_WORK_Rsync_Command: $rsync_command\n\n" if $debug;

#    local(*HIS_IN, *HIS_OUT, *HIS_ERR);
#    sleep(rand($nthreads));
        #my $childpid = open3(
        #   *HIS_IN,
        #   *HIS_OUT,
        #   *HIS_ERR,
        #   "$rsync -aHR -e rsh --delete $sourcepath/$subfolder $destpath"
        #);

        #print  HIS_IN ."\n";
        # Give end of file to kid.
#    my @outlines = <HIS_OUT>;
#    my @errlines = <HIS_ERR>;
#    close HIS_IN;
#    close HIS_OUT;
#    close HIS_ERR;

#    print "STDOUT: @outlines\n" if($debug && @outlines);
#    print "STDERR: @errlines\n" if($debug && @errlines);

        #waitpid($childpid, 0);

#       print "That child exited with wait status of $?\n" if($debug && $?);

#    if (@errlines){
#        my $errcode = 0;
#        foreach my $errline (@errlines) {
#            chomp $errline;
#            ($errcode) = $errline = /.* \(code (\d+)/ ;
#            print "ERRORCODE: $errcode\n" if $debug;
#        }
#        logit($host_source,$subfolder,"Error $errcode - Check .rhosts and /etc/hosts.allow on $host_source");
#    }
#    else{

    logit($work_host, $work_src, "rsync successful!");
}

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

sub chkLastBkp {
    my ($dir) = @_;

    my $bkpExist = 0;   # 0=no backup available, 1=previous backup available
    my ($lastBkp, $msg);

    if (( ! -d $dir ) || ( ! -e "$dir/lastdst")){
        $bkpExist = 0;
        $msg      = "no previous backup found!";
    }
    else{
        $bkpExist = 1;
        $lastBkp  = `cat $dir/lastdst`;
        $msg      = $lastBkp;
        chomp($msg);
    }
    return $bkpExist, $msg;
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
