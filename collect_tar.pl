#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use File::Copy;

# Define remote servers and their corresponding SSH ports
my %nodes = (
    "140.117.60.161" => 20161,
    "140.117.59.182" => 20182,
    "140.117.59.186" => 20186,
    "140.117.59.195" => 22,
    "140.117.59.190" => 22,   # This is the local Rocky Linux server
    "140.117.60.166" => 20166
);

# Set the target directory in /home instead of /root
my $local_dir = "/home/collected_tar_files";

# Ensure the target directory exists
mkdir $local_dir unless -d $local_dir;

# Function to extract last three digits from an IP
sub extract_last_three_digits {
    my ($ip) = @_;
    if ($ip =~ /\.(\d+)$/) {
        return sprintf("%03d", $1);
    }
    return "000";  # Default if extraction fails
}

# Move local tar.gz file first (140.117.59.190)
my $local_ip_last_digits = extract_last_three_digits("140.117.59.190");
my $local_tar_file = "/home/all_sout_cluster${local_ip_last_digits}.tar.gz";
my $local_target = "$local_dir/all_sout_cluster${local_ip_last_digits}.tar.gz";

if (-e $local_tar_file) {
    copy($local_tar_file, $local_target) or warn "Failed to copy local file: $!";
    print "Copied local file $local_tar_file to $local_dir\n";
} else {
    warn "Local file $local_tar_file not found!\n";
}

# Sync files using rsync (for-loop to ensure real-time progress display)
for my $ip (sort keys %nodes) {
    next if $ip eq "140.117.59.190";  # Skip the local server

    my $last_three_digits = extract_last_three_digits($ip);
    my $remote_tar_file = "/home/all_sout_cluster${last_three_digits}.tar.gz";

    print "Syncing from $ip...\n";
    my $rsync_cmd = "rsync -avz --progress -e 'ssh -p $nodes{$ip}' root\@$ip:\"$remote_tar_file\" $local_dir/";
    
    # Use system() to execute rsync and show progress in real-time
    my $exit_status = system($rsync_cmd);
    if ($exit_status != 0) {
        warn "Rsync failed for $ip\n";
    }
}

print "All tar.gz files have been synchronized to $local_dir.\n";
