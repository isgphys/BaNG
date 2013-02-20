use YAML::Tiny qw(LoadFile Dump);
use Data::Dumper;
use threads qw(yield);
use threads::shared;
use Thread::Queue;
use List::MoreUtils qw(uniq);
use POSIX qw(strftime);
use IPC::Open3;
use Net::Ping;
use File::Find::Rule;
use Switch;

my $version         = "1.0";    # BANG Multisync Version
my $debuglevel      = 2;        #1 normal output, 2 ultimate output, 3 + rsync verbose!

my @configfiles;
my %settings;

my @queue;
my $queue_typ       = 0;
my $queue_content   = '';
my $conn_test       = 0;
my $conn_status     = 0;
my $conn_msg        = ('') x 2;

my $host_source = "localhost";

sanityfilecheck($config_default_nis);

#################################
# Sanity checks for programs
#
sanityprogcheck("$global_settings->{RSYNC}");
sanityprogcheck("$global_settings->{BTRFS}");

#################################
# Select Backup Procedure
#
if ( ! $nis_group ) {
    print "Normal-Mode\n" if $debug;
    if ( $target_host ){
        $queue_typ = 1;
        get_queue_folders($target_host, $cfg_group);
        print "Single Host-Mode: $target_host $cfg_group Threads: $settings{$target_host}->{BKP_THREADS_LIMIT}\n" if $debug;
        ($conn_status, $conn_msg ) = chkClientConn($target_host, $settings{$target_host}->{BKP_GWHOST});
        print "$conn_status, $conn_msg\n" if $debug;
        if ($conn_status == 1){
            $conn_test = 1; # online test successful
        }else
        {
            exit 1;
        }
    }
    if ( $bulk_type ){
        print "Bulk Host-Mode: $bulk_type $cfg_group\n" if $debug;
        $queue_typ = 2;
        get_queue_hosts_enabled($cfg_group);
        $conn_test = 0;
    }
}
else{
    print "NIS-Mode\n" if $debug;
    $queue_typ = 3;
    get_queue_nishosts("nishost", $nis_group);
    $conn_test = 0;
}

print "\nBackup sequence: @queue\n\n" if $debug;

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
                case(2) {
                    print "queue_switch: $queue_typ $queue_content\n";
                    print "do_queue_work: $queue_content\n";
                    print "\nQueue BULK HOST Settings of: $queue_content\n";
                    print Dump($settings{$queue_content});
                    print "*** YAML ***\n\n"
                }
                case(3) {
                    print "queue_switch: $queue_typ $host_source $queue_content\n";
                    print "do_queue_work: $host_source $queue_content\n";
                    print "\nQueue CALL NIS Settings of: $queue_content\n";
                    print Dump($settings{$queue_content});
                    print "*** YAML ***\n\n"
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

    switch ($queue_typ) {
        # Single Host backup (Queue < Folders)
        case(1) {
            print "Mach Case: 1\n" if $debug;
            $work_host = $target_host;
            $work_src  = ":$queue_content";
        }
        # Bulk & NIS (Queue < Hosts)
        case[2,3]{
            print "Mach Case: $queue_typ\n" if $debug;
            $work_host = $queue_content;
            $work_src  = $settings{$queue_content}->{BKP_SOURCE_PARTITION};
        }
    }

    if ($conn_test == 0){
        ($conn_status, $conn_msg ) = chkClientConn($work_host, $settings{$work_host}->{BKP_GWHOST});
    }

    if ($conn_status == 1){

        print "do_work: $conn_msg\n" if $debug;
        print "do_work: $work_host $work_src\n" if $debug;

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
    }else
    {
        logit($work_host, $work_src, "backup failed");
        print "do_work: $conn_msg\n" if $debug;
        print "do_work: $work_host FAILED\n" if $debug;
    }
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

sub chkClientConn {
    my ($host, $gwhost) = @_;

    my $state = 0;
    my $msg   = "Host offline";
    my $p     = Net::Ping->new("tcp",2);

    if ($p->ping($host)){
        $state = 1;
        $msg   = "Host online";
    }
    elsif($gwhost){
        $state = 1;
        $msg   = "Host not pingable because behind a Gateway-Host";
    }
    logit($host_source,"INTERNAL", "$host $msg");
    $p->close();

    return $state, $msg;
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

sub get_queue_folders {
    my ($host, $group) = @_;

    print "get_queue_folders: $host, $group\n" if $debug;
    read_configfile($host, $group);

    my (@src_part) = split ( / /, $settings{$host}->{BKP_SOURCE_PARTITION});
    print "Amount of partitions: " . scalar @src_part ." $#src_part\n" if $debug;

    if ( $#src_part == 0 ){
        my $remoteshell  = $settings{$host}->{BKP_RSYNC_RSHELL};
        my $queuedepth   = $settings{$host}->{BKP_QUEUE_DEPTH};

        $src_part[0] =~ s/://;

        my @remotedirlist = `$remoteshell $host find $src_part[0] -mindepth 1 -maxdepth $queuedepth`;

        print "eval subfolders command: @remotedirlist\n" if $debug;

        foreach my $remotedir (@remotedirlist) {
            chomp $remotedir;
            push @queue, $remotedir;
        }
    }else
    {
        foreach my $part (@src_part) {
            $part =~ s/://;
            push @queue, $part;

        }
    }

    return @queue;
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

sub get_queue_nishosts {
    my ($host, $group) = @_;

    my @nishosts = `ypcat auto.$group`;

    read_configfile($host, "NIS");

    my $bkp_target_path = "$settings{$host}->{BKP_TARGET_PATH}/$settings{$host}->{BKP_PREFIX}";

    print "NIS-Data: @nishosts\n" if $debug;

    foreach my $nishost (@nishosts) {
        my ($host,$srcpart) =  $nishost =~ /^([^:]*):(.*)$/;
        # check if backup requested
        if ( -e "$bkp_target_path/$host" ){
	    read_configfile($host, "NIS");
            print "NISHost: $host Partitions: $srcpart\n" if $debug;
            logit($host_source, $host, "add host to queue");
            $settings{$host}->{BKP_SOURCE_PARTITION} = $srcpart;
            push @queue, $host;
        }
        else{
            print "NISHost: $host $srcpart --- NO BACKUP\n" if $debug;
            logit($host_source, $host, "ignoring, no destination directory") if $debug;
        }
    }
    return @queue;
}

sub eval_rsync_options (){
    my ($host) = @_;
    print "Rsync_options_host: $host\n";
    my $rsync_options = '';

    if ( $settings{$host}->{BKP_RSYNC_ARCHIV} ){
        $rsync_options .= "-ax ";
    }
    if ( $settings{$host}->{BKP_RSYNC_RELATIV} ){
        $rsync_options .= "-R ";
    }
    if ($settings{$host}->{BKP_RSYNC_HLINKS}){
        $rsync_options .= "-H ";
    }
    if ($settings{$host}->{BKP_EXCLUDE_FILE}){
        $rsync_options .= "--exclude-from=$config_path/$settings{$host}->{BKP_EXCLUDE_FILE} ";
    }
    if ($settings{$host}->{BKP_RSYNC_RSHELL}){
        if ($settings{$host}->{BKP_GWHOST}){
            $rsync_options .= "-e $settings{$host}->{BKP_RSYNC_RSHELL} $settings{$host}->{BKP_GWHOST} ";
        }else
        {
            $rsync_options .= "-e $settings{$host}->{BKP_RSYNC_RSHELL} ";
        }
    }
    if ($settings{$host}->{BKP_RSYNC_RSHELL_PATH}){
        $rsync_options .= "--rsync-path=$settings{$host}->{BKP_RSYNC_RSHELL_PATH} ";
    }
    if ($settings{$host}->{BKP_RSYNC_DELETE}){
        $rsync_options .= "--delete ";
    }
    if ($settings{$host}->{BKP_RSYNC_DELETE_FORCE}){
        $rsync_options .= "--force ";
    }
    if ($settings{$host}->{BKP_RSYNC_NUM_IDS}){
        $rsync_options .= "--numeric-ids ";
    }
    if ($settings{$host}->{BKP_RSYNC_INPLACE}){
        $rsync_options .= "--inplace ";
    }
    if ($settings{$host}->{BKP_RSYNC_ACL}){
        $rsync_options .= "--acls ";
    }
    if ($settings{$host}->{BKP_RSYNC_XATTRS}){
        $rsync_options .= "--xattrs ";
    }
    if ($settings{$host}->{BKP_RSYNC_OSX}){
       $rsync_options .= "--no-D "
    }
    if ($debug && ($debuglevel == 3)){
       $rsync_options .= "-v "
    }
    print "Rsync Options: $rsync_options\n" if $debug;
    $rsync_options =~ s/\s+$//;
    return $rsync_options;
}

