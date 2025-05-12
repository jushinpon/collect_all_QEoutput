#!/usr/bin/perl
#tail /home/jsp1/QEoutput_database/all_sout_info.txt
#ls /home/jsp1/QEoutput_database/73242
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use File::Basename;
use File::Path qw(make_path);
use File::Find;
use POSIX qw(strftime);
use Parallel::ForkManager;

#system("perl ./mail2report_QEbackup.pl \"For test only!\" \"Hello World!\" \"This is a test message.\"");
#die;
print "Script main.pl for QE database executed at: ", scalar localtime(), "\n";

my $all_sout_info = "/home/jsp1/QEoutput_database/all_sout_info.txt";
my $all_sout_datafolder = "/home/jsp1/QEoutput_database";
my $current_server = "190";  # Local server IP last three digits
# Define remote servers and their corresponding SSH ports
my %server = (
    "140.117.60.161" => 20161,
    "140.117.59.182" => 20182,
   # "140.117.59.186" => 20186,
    "140.117.59.195" => 22,
    "140.117.59.190" => 22,   # This is the local Rocky Linux server
    "140.117.60.166" => 20166
);
my $forkNo = scalar keys %server;
my $pm = Parallel::ForkManager->new("$forkNo");
#do scp to local
my $remote_file = "/root/all_sout_info.txt";
my $local_file = "$all_sout_info";

my $local_dir = "/home/collected_tar_files";#folder to store all tar.gz files
`rm -rf $local_dir`;
mkdir $local_dir unless -d $local_dir;


for my $ser (sort keys %server) {
#$pm->start and next;    
    # 取得本機 IP 的最後三碼
    my @temp = split /\./, $ser;
    chomp($temp[3]);
    my $ip_last_digits = $temp[3];

    my $remote_tar_file = "/home/all_sout_cluster${ip_last_digits}.tar.gz";
    my $local_target = "$local_dir/all_sout_cluster${ip_last_digits}.tar.gz";

    if ($ser eq "140.117.59.190") {
        #`cpan Time::Piece`;
        print "Copying mail2report_QEbackup.pl to $ser...\n";
        system("cp ./mail2report_QEbackup.pl /root/mail2report_QEbackup.pl ");
        system("cp ./recipient.txt /root/recipient.txt ");
        system("cp ./smtp_pass.txt /root/smtp_pass.txt ");

        if ($? == 0) {
            print "Copy mail2report_QEbackup.pl successful to $ser\n";
        } else {
            print "Copy mail2report_QEbackup.pl failed to $ser\n";
            next;
        }
        print "Copying all_sout_info.txt to $ser...\n";
        system("cp $local_file $remote_file");
        if ($? == 0) {
            print "Copy successful to $ser\n";
        } else {
            print "Copy failed to $ser\n";
            next;
        }

        print "Copying find_sout_newdir.pl to $ser...\n";
        system("cp ./find_sout_newdir.pl /root/find_sout_newdir.pl");
        if ($? == 0) {
            print "Copy successful to $ser\n";
        } else {
            print "Copy failed to $ser\n";
            next;
        }

        system("cd /root && perl find_sout_newdir.pl");
        if ($? == 0) {
            print "find_sout_newdir.pl successful to $ser\n";
        } else {
            print "find_sout_newdir.pl failed to $ser\n";
            next;
        }
        #print "Syncing from $ser...\n";
        my $rsync_cmd = "rsync -avz --progress \"$remote_tar_file\" $local_target";
#
        ## Use system() to execute rsync and show progress in real-time
        my $exit_status = system($rsync_cmd);
        if ($exit_status != 0) {#no new sout
            warn "Rsync failed for $ser. No new $remote_tar_file.\n";
            next;
        }
        

        my $tmp_dir = "/home/tmp_qe_extract_workspace";
        `rm -rf $tmp_dir`;
        mkdir $tmp_dir unless -d $tmp_dir;
        # 解壓縮到暫存目錄
        system("tar -xzf \"$local_target\" -C \"$tmp_dir\"") == 0 or die "Failed to extract $remote_tar_file";

        # Load hash numbers from all_sout_info.txt in established database folder
        my %existing_hashes;
        open my $in_fh2, '<', $local_file or die "Cannot open $local_file: $!";
        my $current_max_index = 0;
        while (<$in_fh2>) {
            chomp;
            my ($tag, $hash, $index) = split;
            $existing_hashes{$hash} = "$index";  # Store hash numbers
            $current_max_index = $index if $index > $current_max_index;
        }
        close $in_fh2;
        print "Current max index: $current_max_index\n";

        # Load hash numbers from all_sout_info.txt in the new directory
        #if new sout, modify the old all_sout_info.txt
        open my $in_fh1, '>>', $local_file or die "Cannot open $local_file: $!";

        my $new_txt = "$tmp_dir/all_sout_cluster${ip_last_digits}/all_sout_info.txt";
        my $new_folder = "$tmp_dir/all_sout_cluster${ip_last_digits}";
        my %new_hashes;
        open my $in_fh3, '<', $new_txt or die "Cannot open $new_txt: $!";
        my $new_max_index = 0;
        while (<$in_fh3>) {
            chomp;
            my ($tag, $hash, $index, $path) = split;
            #$existing_hashes{$hash} = "$index";  # Store hash numbers
            $new_max_index = $index if $index > $new_max_index;
            if (exists $existing_hashes{$hash}) {
                print "Duplicate hash found: $hash\n";  # Debugging output
                print "Skipping file:  $path\n";
                next;
            }
            else{#new sout
                $current_max_index++;
                `mkdir -p my $all_sout_datafolder/$current_max_index`;
                `cp $new_folder/$index/* $all_sout_datafolder/$current_max_index/`;
                print $in_fh1 "$tag $hash $current_max_index\n";
                print "New hash found: $hash\n";  # Debugging output
            }
        }
        close $in_fh3;
        close $in_fh1;
        print "New max index: $new_max_index\n";
        #final hoursekeeping
        `rm -rf $tmp_dir`;

    }
    else {#not 190
        print "Copying mail2report_QEbackup.pl to $ser...\n";
        system("scp -P  $server{$ser} ./mail2report_QEbackup.pl root\@$ser:/root/mail2report_QEbackup.pl ");
        system("scp -P  $server{$ser} ./recipient.txt root\@$ser:/root/recipient.txt ");
        system("scp -P  $server{$ser} ./smtp_pass.txt root\@$ser:/root/smtp_pass.txt ");
        if ($? == 0) {
            print "Copy mail2report_QEbackup.pl successful to $ser\n";
        } else {
            print "Copy mail2report_QEbackup.pl failed to $ser\n";
            next;
        }
        print "Copying all_sout_info.txt to $ser...\n";
        system("scp -P  $server{$ser} $local_file root\@$ser:\"$remote_file\" ");
        if ($? == 0) {
            print "Copy successful to $ser\n";
        } else {
            print "Copy failed to $ser\n";
            next;
        }
        print "Copying find_sout_newdir.pl to $ser...\n";
        system("scp -P  $server{$ser} ./find_sout_newdir.pl root\@$ser:/root/find_sout_newdir.pl ");
        if ($? == 0) {
            print "Copy find_sout_newdir.pl successful to $ser\n";
        } else {
            print "Copy find_sout_newdir.pl failed to $ser\n";
            next;
        }
        print "Executing find_sout_newdir.pl on $ser...\n";
        # Execute the script on the remote server
        #system("ssh -p $server{$ser} $ser \"cpan Time::Piece\"");
        system("ssh -p $server{$ser} $ser \"cd /root && perl find_sout_newdir.pl\"");
        print "Syncing from $ser...\n";
        my $rsync_cmd = "rsync -avz --progress -e 'ssh -p $server{$ser}' root\@$ser:\"$remote_tar_file\" $local_target";
#        # Use system() to execute rsync and show progress in real-time
        my $exit_status = system($rsync_cmd);
        if ($exit_status != 0) {#no new sout
            warn "Rsync failed for $ser. No new $remote_tar_file.\n";
            next;
        }
        

        my $tmp_dir    = "/home/tmp_qe_extract_workspace";
        `rm -rf $tmp_dir`;
        mkdir $tmp_dir unless -d $tmp_dir;
        # 解壓縮到暫存目錄
        system("tar -xzf \"$local_target\" -C \"$tmp_dir\"") == 0 or die "Failed to extract $remote_tar_file";

        # Load hash numbers from all_sout_info.txt in established database folder
        my %existing_hashes;
        open my $in_fh2, '<', $local_file or die "Cannot open $local_file: $!";
        my $current_max_index = 0;
        while (<$in_fh2>) {
            chomp;
            my ($tag, $hash, $index) = split;
            $existing_hashes{$hash} = "$index";  # Store hash numbers
            $current_max_index = $index if $index > $current_max_index;
        }
        close $in_fh2;
        print "Current max index: $current_max_index\n";

        # Load hash numbers from all_sout_info.txt in the new directory
        #if new sout, modify the old all_sout_info.txt
        open my $in_fh1, '>>', $local_file or die "Cannot open $local_file: $!";

        my $new_txt = "$tmp_dir/all_sout_cluster${ip_last_digits}/all_sout_info.txt";
        my $new_folder = "$tmp_dir/all_sout_cluster${ip_last_digits}";
        my %new_hashes;
        open my $in_fh5, '<', $new_txt or die "Cannot open $new_txt: $!";
        my $new_max_index = 0;
        while (<$in_fh5>) {
            chomp;
            my ($tag, $hash, $index, $path) = split;
            #$existing_hashes{$hash} = "$index";  # Store hash numbers
            $new_max_index = $index if $index > $new_max_index;
            if (exists $existing_hashes{$hash}) {
                print "Duplicate hash found: $hash\n";  # Debugging output
                print "Skipping file:  $path\n";
                next;
            }
            else{#new sout
                $current_max_index++;
                `mkdir -p my $all_sout_datafolder/$current_max_index`;
                `cp $new_folder/$index/* $all_sout_datafolder/$current_max_index/`;
                print $in_fh1 "$tag $hash $current_max_index\n";
                #print "New hash found: $hash\n";  # Debugging output
            }
        }
        close $in_fh5;
        close $in_fh1;
        print "New max index: $new_max_index\n";
        
        #final hoursekeeping
        `rm -rf $tmp_dir`;
    }
    
#$pm->finish;    
} 

#$pm->wait_all_children;


print "All processes completed.\n";