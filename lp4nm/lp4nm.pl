#!/usr/bin/perl -w
use IO::Handle;
use File::Tail;
use POSIX 'setsid';
use LWP::Simple;


use POSIX ();
use FindBin ();
use File::Basename ();
use File::Spec::Functions;

use GDBM_File;
use SDBM_File;
use Getopt::Long;


my $VERSION = "Build 2008-09-16, 2008-08-15, 2008-01-29, 2013-01-31";

my $daemon_logfile = '/var/tmp/log_processor4nm.log';
my $daemon_pidfile = '/var/tmp/log_processor4nm.pid';

my $csv_file = '/var/tmp/log_processor4nm.csv';

my $dbm_queue_file = '/var/tmp/log_processor4nm_dbm_queue';
my %fm_queue_list;

my $url="http://127.0.0.1/cgi-bin/snmr";

my $dbh;
my $sth;


my $logfile;
my $file;


my %opt = ();

sub daemonize();
sub sigHUG_handler();
sub sigTERM_handler();
sub read_from_dbm();
sub write_to_dbm();
sub dbh_close();
sub to_date_time;
sub process_log();
sub usage();
sub main();



$|=1;
my $script = File::Basename::basename($0);
$script = "$script"." @ARGV";
my $SELF = catfile $FindBin::Bin, $script;

my $sigsetHUP = POSIX::SigSet->new();
my $sigsetTERM = POSIX::SigSet->new();
my $actionHUP = POSIX::SigAction->new('sigHUP_handler',
                                   $sigsetHUP,
                                   &POSIX::SA_NODEFER);
my $actionTERM = POSIX::SigAction->new('sigTERM_handler',
                                   $sigsetTERM,
                                   &POSIX::SA_NODEFER);
POSIX::sigaction(&POSIX::SIGHUP, $actionHUP);
POSIX::sigaction(&POSIX::SIGTERM, $actionTERM);

sub usage()
{
	print "usage: log_processor4nm [*options*]\n\n";
	print "  -h, --help         display this help and exit\n";
	print "  -v, --verbose      be verbose about what you do\n";
	print "  -V, --version      output version information and exit\n";
	print "  -p, --perfdata-logfile perfdata-log    monitor perfdata logfile f instead of /opt/nginx/logs/error.log\n";
	print "  -d, --daemon       start in the background\n";
	print "  --with-db=mysql     write all data to mysql database\n";
	print "  --with-csv-file=FILE    write CSV FILE instead of /var/tmp/log_processor4nm.csv\n";
	print "  --dbm-queue-file=FILE  write temp data to FILE instead of /var/tmp/log_processor4nm_dbm_queue\n";
	print "  --daemon-pid=FILE  write PID to FILE instead of /var/tmp/log_processor4nm.pid\n";
	print "  --daemon-log=FILE  write verbose-log to FILE instead of /var/tmp/log_processor4nm.log\n";

	exit;
}

sub main()
{
	Getopt::Long::Configure('no_ignore_case');
	GetOptions(\%opt, 'help|h',  'perfdata_logfile|p=s', 'version|V',
		'verbose|v', 'daemon|d!', 'daemon_pid|daemon-pid=s', 'dbm_queue_file|dbm-queue-file=s',
		'daemon_log|daemon-log=s','with_csv_file|with-csv-file=s','with_db|with-db=s'
		) or exit(1);
	usage if $opt{help};

	if($opt{version}) {
		print "log_processor $VERSION by chnl\@163.com. And MSN is the same account.\n";
		exit;
	}

	$daemon_pidfile = $opt{daemon_pid} if defined $opt{daemon_pid};
	$daemon_logfile = $opt{daemon_log} if defined $opt{daemon_log};


	daemonize if $opt{daemon};

	$dbm_queue_file = $opt{dbm_queue_file} if defined $opt{dbm_queue_file};

	if($opt{with_db}) {
		if($opt{with_db} =~/^mysql$/i) {
			use DBI;
			$dbh=DBI->connect("DBI:mysql:database=log_processor;host=localhost","npdp","npdp",{'RaiseError'=>1});
			$sth=$dbh->prepare("INSERT INTO npdp_perf(date_time,host_name,service_desc,perf_data)VALUES(?,?,?,?)");
		}
	}

	if($opt{with_csv_file}) {
		$csv_file = $opt{with_csv_file};
		open CSV, ">>$csv_file"
			or die "log_processor: can't write to $csv_file: $!";
	}
	else {
		open CSV, '>/dev/null'
			or die "log_processor: can't write to /dev/null: $!";
	}


	$perfdata_logfile = defined $opt{perfdata_logfile} ? $opt{perfdata_logfile} : '/opt/nginx/logs/error.log';
	read_from_dbm;
	$file=File::Tail->new(name=>$perfdata_logfile, maxinterval=>120, adjustafter=>7);
	process_log;
}



sub daemonize()
{
	open STDIN, '/dev/null' or die "log_processor: can't read /dev/null: $!";
	if($opt{verbose}) {
		open STDOUT, ">>$daemon_logfile"
			or die "log_processor: can't write to $daemon_logfile: $!";
	}
	else {
		open STDOUT, '>/dev/null'
			or die "log_processor: can't write to /dev/null: $!";
	}
	defined(my $pid = fork) or die "log_processor: can't fork: $!";
	if($pid) {
		# parent
		open PIDFILE, ">$daemon_pidfile"
			or die "log_processor: can't write to $daemon_pidfile: $!\n";
		print PIDFILE "$pid\n";
		close(PIDFILE);
		exit;
	}
	# child
	setsid			or die "log_processor: can't start a new session: $!";
	open STDERR, '>&STDOUT' or die "log_processor: can't dup stdout: $!";
}

sub sigHUP_handler()
{
	open SIG, '>>./log_processor4nm.sig';
	print SIG "got SIGHUP\n";
	write_to_dbm;
	dbh_close;
	#exec($SELF, @ARGV) or die "Couldn't restart: $!\n";
	exec($SELF) or die "Couldn't restart: $!\n";
}

sub sigTERM_handler()
{
	open SIG, '>>./log_processor4nm.sig';
	print SIG "got SIGTERM\n";
	write_to_dbm;
	dbh_close;
	exit(0);
}


sub read_from_dbm()
{
	dbmopen (%fm_queue_list, $dbm_queue_file, 0666) or die "Couldn't open file: $!";
}

sub write_to_dbm()
{
	dbmclose (%fm_queue_list) or die "Couldn't write to file: $!";
}


sub dbh_close()
{
	$dbh->disconnect() if($dbh);

}

sub to_date_time
{
	my($log_date) = @_;
	my $log_date_cmd = "\`date -d '\$log_date\' \'\+\%F \%T\'\`;";
	my $date_time = eval($log_date_cmd);
	return $date_time;
}



sub process_log()
{
	while (defined($line=$file->read)) {
		if ($line =~ /No\ such\ file\ or\ directory/) {
			print  ("####verbose detail#####\n"."$line\n");
			#if($sth) {
			#	$sth->execute($date_time,$host_name,$service_desc,$perf_data);
			#}
			#print CSV "$line\n";
			@array = split(/\ /, $line);
			if ($array[5] =~ /open\(\)/) {
				$uri = $array[6];
			}
			else {
		
				$uri = $array[5];
			}
			print CSV "$uri\n";
			$content = get("$url?host=c168&service=nginx_log_404_check&severity=2&msg=$uri failed");
			print "$url?host=c168&service=nginx_log_404_check&severity=2&msg=$uri\n";
			print "response: $content\n";
		}

	}
}

main;
