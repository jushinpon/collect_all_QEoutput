#!/usr/bin/perl
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use File::Basename;
use File::Path qw(make_path);
use File::Find;
use File::Copy;
use POSIX qw(strftime);
use File::stat;

# Get last three digits of the IP address
my $ip_last_digits = `ip a | grep 'inet 140.117' | awk '{print \$2}' | cut -d'.' -f4 | cut -d'/' -f1`;
chomp($ip_last_digits);
$ip_last_digits = "000" if $ip_last_digits eq "";  # Default if IP extraction fails

# Define the new output directory
my $output_dir = "/home/all_sout_cluster$ip_last_digits";

# Rename old directories with a unique sequential numbering
if (-d $output_dir) {
    my $new_suffix = 1;
    my $backup_dir;

    # Find the next available backup directory name
    do {
        $backup_dir = sprintf("/home/all_sout_cluster%s%02d", $ip_last_digits, $new_suffix);
        $new_suffix++;
    } while (-d $backup_dir);  # Keep increasing the number if the folder exists

    rename $output_dir, $backup_dir or die "Failed to rename $output_dir to $backup_dir: $!";
    print "Old directory renamed to $backup_dir\n";
}

# Create the new output directory
make_path($output_dir) or die "Failed to create $output_dir: $!";

# Find all `.sout` files under `/home`, excluding symbolic links and folders containing "all_sout_cluster"
my @sout_files;
find(
    sub {
        return if -l $_;                       # Skip symbolic links
        return if $File::Find::dir =~ /all_sout_cluster/;  # Skip directories with "all_sout_cluster"
        return unless -f $_ && /\.sout$/;      # Only process .sout files
        push @sout_files, $File::Find::name;
    },
    "/home"
);

# Counter for SCF numbering and duplicate folder tracking
my $scf_counter = 0;
my %folder_counts;
my @info_entries;
my %file_registry;

foreach my $sout_file (@sout_files) {
    # Get file prefix and parent directory
    my ($filename, $directories, $suffix) = fileparse($sout_file, ".sout");
    my $parent_dir = dirname($sout_file);
    my $input_file = "$parent_dir/$filename.in";

    # Skip if no corresponding QE input file
    next unless -e $input_file;
    next if -l $input_file;  # Skip symbolic (soft) link input files

    # Compute MD5 hash of QE input file
    open my $in_fh, '<', $input_file or next;
    my $content = do { local $/; <$in_fh> };
    close $in_fh;
    my $file_hash = md5_hex($content);

    # Check for "JOB DONE" in sout file using `tac`
    my $job_done = system("tac \"$sout_file\" | grep -m1 'JOB DONE' > /dev/null") == 0;
    next unless $job_done;

    # Check if input file contains `relax` or `vc-relax`
    open my $in_fh2, '<', $input_file or next;
    my $skip_copy = 0;
    while (<$in_fh2>) {
        if (/calculation\s*=\s*"?(relax|vc-relax)"?/) {
            $skip_copy = 1;
            last;
        }
    }
    close $in_fh2;
    
    next if $skip_copy;  # Skip if relax/vc-relax is found

    # Get parent folder name and handle duplicates
    my $parent_folder = basename($parent_dir);
    $folder_counts{$parent_folder}++;
    my $folder_suffix = ($folder_counts{$parent_folder} > 1) ? sprintf("_%02d", $folder_counts{$parent_folder}) : "";
    my $target_dir = "$output_dir/${parent_folder}${folder_suffix}";

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

    # Store info entry with MD5 hash and source directory
    if ($element_string) {
        push @info_entries, "$element_string $target_sout $file_hash $parent_dir";
        $file_registry{$target_sout} = $target_input;  # Track copied files
    }
}

# Write all_sout_info.txt
my $info_file = "$output_dir/all_sout_info.txt";
open my $info_fh, '>', $info_file or die "Cannot open $info_file: $!";
print $info_fh "$_\n" for @info_entries;
close $info_fh;

print "Processing complete. Element information stored in $info_file.\n";

# ======================================================
# Remove old tar.gz file if it exists
# ======================================================
my $tar_file = "/home/all_sout_cluster${ip_last_digits}.tar.gz";
if (-e $tar_file) {
    system("rm \"$tar_file\"") == 0 or die "Failed to remove old tar.gz file: $!";
    print "Old tar.gz file removed: $tar_file\n";
}

# ======================================================
# Create a tar.gz archive for all_sout_cluster$ip_last_digits
# ======================================================
system("tar -czf \"$tar_file\" -C \"/home\" \"all_sout_cluster$ip_last_digits\"") == 0
    or die "Failed to create tar.gz archive: $!";

print "Archive created: $tar_file\n";
