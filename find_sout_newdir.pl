#!/usr/bin/perl
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use File::Basename;
use File::Path qw(make_path);
use File::Find;
use POSIX qw(strftime);

# 取得本機 IP 的最後三碼
my $ip_last_digits = `ip a | grep 'inet 140.117' | awk '{print \$2}' | cut -d'.' -f4 | cut -d'/' -f1`;
chomp($ip_last_digits);
$ip_last_digits = "000" if $ip_last_digits eq "";

# 定義輸出資料夾與壓縮檔案名稱
my $output_dir = "/home/all_sout_cluster$ip_last_digits";
my $tar_file = "$output_dir.tar.gz";

# 若 output_dir 已存在，備份舊版本
if (-d $output_dir) {
    my $backup_id = 1;
    my $backup_dir;
    do {
        $backup_dir = "${output_dir}_bak$backup_id";
        $backup_id++;
    } while (-d $backup_dir);
    rename $output_dir, $backup_dir or die "Cannot rename $output_dir to $backup_dir: $!";
    print "Old output dir moved to $backup_dir\n";
}
make_path($output_dir);

# 掃描所有 .sout 檔案
my @sout_files;
find(
    sub {
        return if -l $_;
        return if $File::Find::dir =~ /all_sout_cluster/;
        return unless -f $_ && /\.sout$/;
        push @sout_files, $File::Find::name;
    },
    "/home"
);

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
    my $content = do { local $/; <$in_fh2> };
    close $in_fh2;
    my $file_hash = md5_hex($content);

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
    push @info_entries, "$element_str $file_hash $folder_index";

    $folder_index++;
}

# 寫入 all_sout_info.txt
open my $info_fh, '>', "$output_dir/all_sout_info.txt" or die "Cannot write info file: $!";
print $info_fh "$_\n" for @info_entries;
close $info_fh;

print "✅ 整理完成，共處理 ", scalar(@info_entries), " 筆資料。\n";

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
