#!/usr/bin/perl
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use File::Basename;
use File::Path qw(make_path);
use File::Find;
use POSIX qw(strftime);
use Time::Piece;
use Time::Seconds;



my $days = 3;  # Set the number of days
my $time_limit = time - ($days * 86400);  # Convert days to seconds

# Define the hash file path
my $hash_file = "/root/all_sout_info.txt";
my %existing_hashes;

# Load hash numbers from all_sout_info.txt
open my $in_fh2, '<', $hash_file or die "Cannot open $hash_file: $!";
while (<$in_fh2>) {
    my ($tag, $hash, $index) = split;
    $existing_hashes{$hash} = "elem: $tag and folder: $index";  # Store hash numbers
}
close $in_fh2;

# 取得本機 IP 的最後三碼
my $ip_last_digits = `ip a | grep 'inet 140.117' | awk '{print \$2}' | cut -d'.' -f4 | cut -d'/' -f1`;
chomp($ip_last_digits);
$ip_last_digits = "000" if $ip_last_digits eq "";

# 定義輸出資料夾與壓縮檔案名稱
my $output_dir = "/home/all_sout_cluster$ip_last_digits";
my $tar_file = "$output_dir.tar.gz";

if (-d $output_dir) {
    my $backup_id = 1;
    my $backup_dir;

    # Find the next available backup directory name
    do {
        $backup_dir = "${output_dir}_bak$backup_id";
        $backup_id++;
    } while (-d $backup_dir);
    
    # Rename the existing output directory to the backup name
    rename $output_dir, $backup_dir or die "Cannot rename $output_dir to $backup_dir: $!";
    print "Old output dir moved to $backup_dir\n";

    # Collect existing backups, sorted in descending order
    my @backups = sort { $b cmp $a } glob "${output_dir}_bak*";

    # Rename older backups to maintain only three and keep ordering
    if (@backups > 3) {
        for (my $i = 3; $i < @backups; $i++) {
            system("rm -rf $backups[$i]") == 0 or warn "Failed to remove $backups[$i]: $!";
            print "Deleted old backup: $backups[$i]\n";
        }
    }

    # Reorder remaining backups to `output_bak1`, `output_bak2`, `output_bak3`
    my @latest_backups = sort glob "${output_dir}_bak*";
    for (my $i = 0; $i < @latest_backups; $i++) {
        my $new_name = "${output_dir}_bak" . ($i + 1);
        rename $latest_backups[$i], $new_name or warn "Failed to rename $latest_backups[$i] to $new_name";
        print "Renamed $latest_backups[$i] -> $new_name\n";
    }
}
# 建立新的輸出資料夾
`rm -rf $output_dir` if -d $output_dir;  # 清除舊的資料夾
make_path($output_dir);

# Scan for .sout files

#find normal users
my @users;

# Open /etc/passwd to read user details
open my $fh, '<', "/etc/passwd" or die "Cannot open /etc/passwd: $!";
while (<$fh>) {
    my ($username, $passwd, $uid, $gid, $desc, $home, $shell) = split(':');
    
    # Skip system users (UIDs below 1000 are usually system users)
    next if $uid < 1000;
    
    push @users, $username;  # Add normal users to the array
}
close $fh;

# Generate search paths based on users
my @search_paths = map { "/home/$_" } @users;

my @sout_files;
find(
    sub {
        #print "Checking $_\n";  # Debugging output
        return if -l $_;  # Skip symbolic links
        return if $File::Find::dir =~ /all_sout_cluster/;  # Ignore specific directories
        return if $File::Find::dir =~ /QEoutput_database/;  # Ignore specific directories
        return unless -f $_ && /\.sout$/;  # Only process .sout files
        my $mod_time = (stat($_))[9];  # Get modification time
        return unless $mod_time >= $time_limit;  # Only files modified in the last $days
        push @sout_files, $File::Find::name;
    },
    @search_paths  # Only search user directories
);

# Print results
#print "\nUnique .sout files in cluster $ip_last_digits:\n", join("\n", @sout_files), "\n";

# 開始逐筆處理
my $folder_index = 1;
my @info_entries;

foreach my $sout_file (@sout_files) {
    my ($filename, $directories, $suffix) = fileparse($sout_file, ".sout");
    my $parent_dir = dirname($sout_file);
    my $input_file = "$parent_dir/$filename.in";

    next unless -e $input_file && !-l $input_file;

    # 檢查是否有 "JOB DONE"
    my $job_done = system("tac \"$sout_file\" | grep -m1 'JOB DONE' > /dev/null") == 0;
    next unless $job_done;

    # 跳過 relax/vc-relax 類型
    open my $in_fh, '<', $input_file or next;
    my $skip = 0;
    while (<$in_fh>) {
        if (/calculation\s*=\s*"?(relax|vc-relax)"?/) {
            $skip = 1;
            last;
        }
    }
    close $in_fh;
    next if $skip;

    # 計算 input hash
    open my $in_fh2, '<', $input_file or next;
    binmode $in_fh2;  # Ensure raw data reading
    my $content = do { local $/; <$in_fh2> };
    close $in_fh2;
    my $file_hash = md5_hex($content);

    if (exists $existing_hashes{$file_hash}) {
        print "Duplicate hash found: $file_hash\n";  # Debugging output
        print "Skipping file:  $input_file\n";
        next;
    }

    # 擷取元素
    my %elements;
    open my $in_fh3, '<', $input_file or next;
    while (<$in_fh3>) {
        if (/ATOMIC_SPECIES/) {
            while (<$in_fh3>) {
                last if /^\s*$/;
                my @cols = split;
                $elements{$cols[0]} = 1 if $cols[0] =~ /^[A-Z][a-z]?$/;
            }
        }
    }
    close $in_fh3;

    my $element_str = join("-", sort keys %elements);
    next unless $element_str;

    # 建立資料夾並複製檔案
    my $current_dir = "$output_dir/$folder_index";
    make_path($current_dir);
    system("cp \"$sout_file\" \"$current_dir/$filename.sout\"");
    system("cp \"$input_file\" \"$current_dir/$filename.in\"");

    # 紀錄資訊
    push @info_entries, "$element_str $file_hash $folder_index $input_file";

    $folder_index++;
}

if (@info_entries == 0) {
    print "❌ *****沒有找到符合條件的 .sout 檔案 at $ip_last_digits。\n";
    `rm -rf $output_dir`;  # 清除空的資料夾
    print "🗑️  已移除空的資料夾：$output_dir\n";
    #system("perl ./mail2report_QEbackup.pl \"No new sout at $ip_last_digits\" \"No new sout files found at cluster $ip_last_digits!\"");
    if (-e $tar_file) {
        unlink $tar_file or die "Failed to remove old tar.gz file: $!";
        print "🗑️  舊壓縮檔已移除：$tar_file\n";
    }
    exit;
}

system("perl ./mail2report_QEbackup.pl \"find new sout at $ip_last_digits\" \"New sout files found at cluster $ip_last_digits!\"");

# 寫入 all_sout_info.txt
open my $info_fh, '>', "$output_dir/all_sout_info.txt" or die "Cannot write info file: $!";
print $info_fh "$_\n" for @info_entries;
close $info_fh;

print "✅ *****整理完成，共處理 ", scalar(@info_entries), " 筆資料 at $ip_last_digits。\n";

# 移除舊的壓縮檔（若存在）
if (-e $tar_file) {
    unlink $tar_file or die "Failed to remove old tar.gz file: $!";
    print "🗑️  舊壓縮檔已移除：$tar_file\n";
}

# 建立新的壓縮檔
my $tar_base = basename($output_dir);
system("tar -czf \"$tar_file\" -C \"/home\" \"$tar_base\"") == 0
    or die "❌ Failed to create tar.gz archive: $!";
print "📦 壓縮完成：$tar_file\n";
