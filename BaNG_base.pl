use YAML::Tiny qw(LoadFile Dump);
use threads qw(yield);
use threads::shared;
use Thread::Queue;
use List::MoreUtils qw(uniq);
use POSIX qw(strftime);
use IPC::Open3;
use File::Find::Rule;
use Switch;

my $queue_typ       = 0;
my $queue_content   = '';
my $host_source = "localhost";

#################################
# Sanity checks for programs
#
sanityprogcheck("$global_settings->{RSYNC}");
sanityprogcheck("$global_settings->{BTRFS}");


#*****************************************************************
# Threading setup
#
my $Q = Thread::Queue->new;
my @threads = map threads->create( \&thread, $Q ), 1 .. $nthreads;
$Q->enqueue($_) for sort @queue;
$Q->enqueue( (undef) x $nthreads );
$_->join for @threads;

sub thread {
    my $Q   = shift;
    my $tid = threads->tid;
    while (my $queue_content = $Q->dequeue) {

        #****** do work ******
        logit($host_source, $queue_content, "initialize backup sequence");

        if ($debug && ($debuglevel == 2)) {
            switch ($queue_typ) {
                case(1) {
                    print "queue_switch: $queue_typ $target_host $queue_content\n";
                    print "do_queue_work: $target_host $queue_content\n";
                }
                else    {
                    print "queue_switch: $queue_typ - wrong queue_typ\n";
                }
            }
        }

        do_work($queue_typ, $queue_content, $conn_test);

        logit($host_source, $queue_content , "backup sequence done");

        #****** end work ******
    }
}

#********************************************************************
# Subroutine
#*******************************************************************-

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

sub get_queue_hosts_enabled {
    my ($kat) = @_;

    @configfiles = find_enabled_hosts("*_$kat.yaml", $path_enabled);

    print "Find enabled config: @configfiles\n" if $debug;

    foreach my $configfile (@configfiles) {
        my ($bulkhost) = $configfile =~ /^([\w\d-]+)_[\w\d-]+\.yaml/;
        read_configfile($bulkhost, $kat);
        print "Extracted bulk Hostname: $bulkhost\n" if $debug;
        push @queue, $bulkhost;
    }
    return @queue;
}
