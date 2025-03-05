#!/usr/bin/perl
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use File::Basename;
use File::Path qw(make_path);
use File::Find;
use File::Copy;
use POSIX qw(strftime);

# Get last three digits of the IP address
my $ip_last_digits = `ip a | grep 'inet 140.117' | awk '{print \$2}' | cut -d'.' -f4 | cut -d'/' -f1`;
chomp($ip_last_digits);
$ip_last_digits = "000" if $ip_last_digits eq "";  # Default if IP extraction fails

# Define the new output directory
my $output_dir = "/home/all_sout_cluster$ip_last_digits";

# Identify and rename old directories
my @existing_dirs = glob("/home/all_sout_cluster${ip_last_digits}*");
my $max_suffix = 0;
my %existing_md5_hashes;

foreach my $dir (@existing_dirs) {
    if ($dir =~ /all_sout_cluster${ip_last_digits}(\d{2})$/) {
        $max_suffix = $1 if $1 > $max_suffix;
    }
    # Read MD5 hashes from existing all_sout_info.txt files
    my $info_file = "$dir/all_sout_info.txt";
    if (-e $info_file) {
        open my $fh, '<', $info_file or next;
        while (<$fh>) {
            if (/(\S+)\s+(\S+)\s+([a-f0-9]{32})$/) {
                my ($elements, $filepath, $md5) = ($1, $2, $3);
                $existing_md5_hashes{$md5} = 1;  # Store existing MD5 hashes
            }
        }
        close $fh;
    }
}

if (-d $output_dir) {
    my $new_suffix = sprintf("%02d", $max_suffix + 1);
    my $backup_dir = "${output_dir}${new_suffix}";
    rename $output_dir, $backup_dir or die "Failed to rename $output_dir to $backup_dir: $!";
    print "Old directory renamed to $backup_dir\n";
}

# Create the new output directory
make_path($output_dir) or die "Failed to create $output_dir: $!";

# Use `find` to get up to 10 `.sout` files, excluding all_sout_clusterXXX
my @sout_files = `find /home -type f -name "*.sout" ! -path "$output_dir/*"`;
map { s/^\s+|\s+$//g; } @sout_files;  # Trim whitespace

# Counter for SCF numbering
my $scf_counter = 0;
my @info_entries;
my %file_registry;
my %content_hash;

foreach my $sout_file (@sout_files) {
    # Get file prefix and parent directory
    my ($filename, $directories, $suffix) = fileparse($sout_file, ".sout");
    my $parent_dir = dirname($sout_file);
    my $input_file = "$parent_dir/$filename.in";

    # Skip if no corresponding QE input file
    next unless -e $input_file;

    # Compute hash of the QE input file content
    open my $in_fh2, '<', $input_file or next;
    my $content = do { local $/; <$in_fh2> };
    close $in_fh2;
    my $file_hash = md5_hex($content);

    # If the file already exists in an old directory, skip it
    if (exists $existing_md5_hashes{$file_hash}) {
        print "Skipping existing input file: $input_file (MD5 match found in old folders)\n";
        next;
    }

    # Check for "JOB DONE" in sout file using `tac`
    my $job_done = system("tac \"$sout_file\" | grep -m1 'JOB DONE' > /dev/null") == 0;
    next unless $job_done;

    # Check if input file contains `relax` or `vc-relax`
    open my $in_fh, '<', $input_file or next;
    my $skip_copy = 0;
    while (<$in_fh>) {
        if (/calculation\s*=\s*"?(relax|vc-relax)"?/) {
            $skip_copy = 1;
            last;
        }
    }
    close $in_fh;
    
    next if $skip_copy;  # Skip if relax/vc-relax is found

    # Get parent folder name
    my $parent_folder = basename($parent_dir);
    my $target_dir = "$output_dir/$parent_folder";

    # Check if the filename contains "lmp_"
    if ($filename =~ /lmp_/) {
        $scf_counter++;
        $target_dir = "$output_dir/labelled/scf_$scf_counter";
    }

    # Create output directory only if needed
    make_path($target_dir) unless -d $target_dir;

    # Copy sout and input files
    my $target_sout = "$target_dir/$filename.sout";
    my $target_input = "$target_dir/$filename.in";

    system("cp \"$sout_file\" \"$target_sout\"") unless -e $target_sout;
    system("cp \"$input_file\" \"$target_input\"") unless -e $target_input;

    # Extract elements from QE input file
    open my $in_fh3, '<', $target_input or next;
    my %elements;
    while (<$in_fh3>) {
        if (/ATOMIC_SPECIES/) {
            while (<$in_fh3>) {
                last if /^\s*$/;  # Stop at blank line
                my @cols = split;
                $elements{$cols[0]} = 1 if $cols[0] =~ /^[A-Z][a-z]?$/;  # Ensure valid element names
            }
        }
    }
    close $in_fh3;

    # Sort and format elements as "Ag-Au-Cu"
    my $element_string = join("-", sort keys %elements);

    # Store info entry with MD5 hash
    if ($element_string) {
        push @info_entries, "$element_string $target_sout $file_hash";
        $file_registry{$target_sout} = $target_input;  # Track copied files
    }
}

# Write all_sout_info.txt
my $info_file = "$output_dir/all_sout_info.txt";
open my $info_fh, '>', $info_file or die "Cannot open $info_file: $!";
print $info_fh "$_\n" for @info_entries;
close $info_fh;

print "Processing complete. Element information stored in $info_file.\n";

# ===================================================
# Step 2: Remove duplicate `.sout` and `.in` files
# ===================================================
print "Removing duplicate QE input and sout files based on identical content...\n";
my $removed_duplicates_file = "$output_dir/removed_duplicates.txt";
open my $removed_fh, '>', $removed_duplicates_file or die "Cannot open $removed_duplicates_file: $!";

foreach my $hash (keys %content_hash) {
    my $original_file = $content_hash{$hash}{original};
    foreach my $duplicate_file (@{ $content_hash{$hash}{duplicates} }) {
        # Find corresponding `.sout` file
        my ($duplicate_filename, $duplicate_dir) = fileparse($duplicate_file, ".in");
        my $duplicate_sout = "$duplicate_dir/$duplicate_filename.sout";

        # Record deleted files
        print $removed_fh "Duplicate QE Input: $duplicate_file\n";
        print $removed_fh "Duplicate QE Output: $duplicate_sout\n";
        print $removed_fh "Kept Reference: $original_file\n\n";

        # Delete duplicate files
        unlink $duplicate_file if -e $duplicate_file;
        unlink $duplicate_sout if -e $duplicate_sout;
    }
}
close $removed_fh;

print "Duplicate removal complete. Removed files logged in $removed_duplicates_file.\n";
