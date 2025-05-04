#!/usr/bin/perl
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use File::Basename;
use File::Path qw(make_path);
use File::Find;
use POSIX qw(strftime);

system("perl ./mail2report_QEbackup.pl \"Hello World!\" \"This is a test message.\"");
die;

my $all_sout_info = "/home/jsp1/QEoutput_database/all_sout_info.txt";
my $current_server = "190";  # Local server IP last three digits
# Define remote servers and their corresponding SSH ports
my %server = (
    "140.117.60.161" => 20161,
    #"140.117.59.182" => 20182,
    #"140.117.59.186" => 20186,
    #"140.117.59.195" => 22,
    #"140.117.59.190" => 22,   # This is the local Rocky Linux server
    #"140.117.60.166" => 20166
);

#do scp to local
my $remote_file = "/root/all_sout_info.txt";
my $local_file = "$all_sout_info";

for my $ser (sort keys %server) {
    # 取得本機 IP 的最後三碼
    my $ip_last_digits = `ip a | grep 'inet 140.117' | awk '{print \$2}' | cut -d'.' -f4 | cut -d'/' -f1`;
    chomp($ip_last_digits);
   
    if ($ip_last_digits) {
        die "QEouput not backuped in $ser!\n";
        system("perl ./mail2report_QEbackup.pl \"Hello World!\" \"This is a test message.\""); 

    }
    
    print "Copying from $ser...\n";
    system("scp -P  $server{$ser} ./mail2report_QEbackup.pl root\@$ser:\"$remote_file\" ");
    if ($? == 0) {
        print "Copy successful to $ser\n";
    } else {
        print "Copy failed to $ser\n";
        next;
    }


    print "Copying from $ser...\n";
    system("scp -P  $server{$ser} $local_file root\@$ser:\"$remote_file\" ");
    if ($? == 0) {
        print "Copy successful to $ser\n";
    } else {
        print "Copy failed to $ser\n";
        next;
    }

    system("scp -P  $server{$ser} /root/collect_all_QEoutput/find_sout_newdir.pl root\@$ser:/root/find_sout_newdir.pl ");
    if ($? == 0) {
        print "Copy find_sout_newdir.pl successful to $ser\n";
    } else {
        print "Copy find_sout_newdir.pl failed to $ser\n";
        next;
    }

}    