#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use File::Basename;
use Cwd;

# 設定路徑
my $source_dir = "/home/collected_tar_files";
my $db_dir     = "/home/jsp1/QEoutput_database";
my $tmp_dir    = "/home/tmp_qe_extract_workspace";  # 安全暫存區域

# ❗檢查根目錄空間是否足夠
my $root_usage = `df -P / | tail -1`;
my @cols = split(/\s+/, $root_usage);
my $avail_kb = $cols[3];
my $avail_gb = int($avail_kb / 1024 / 1024);
if ($avail_gb < 5) {
    die "[ERROR] Root filesystem has less than 5 GB free. Aborting to avoid crash.\n";
}

# 建立必要資料夾
make_path($db_dir) unless -d $db_dir;
make_path($tmp_dir) unless -d $tmp_dir;

# 去重控制與資訊彙整
my %hash_seen;
my @summary;
my $folder_index = 1;

# 開始處理每個 tar.gz
opendir(my $dh, $source_dir) or die "Cannot open $source_dir: $!";
my @tars = grep { /\.tar\.gz$/ } readdir($dh);
closedir($dh);

foreach my $tarfile (@tars) {
    my $full_tar = "$source_dir/$tarfile";
    print "🔍 Processing $tarfile...\n";

    # 清空暫存資料夾
    if (-d $tmp_dir) {
        remove_tree($tmp_dir, { keep_root => 1 });
    }

    # 解壓縮到暫存目錄
    system("tar -xzf \"$full_tar\" -C \"$tmp_dir\"") == 0 or die "Failed to extract $tarfile";

    # 處理其中的 all_sout_info.txt 與子資料夾
    my @folders = glob("$tmp_dir/all_sout_cluster*");
    foreach my $cluster_dir (@folders) {
        my $info_file = "$cluster_dir/all_sout_info.txt";
        next unless -e $info_file;

        open my $fh, "<", $info_file or die "Cannot open $info_file: $!";
        while (<$fh>) {
            chomp;
            my ($elements, $hash, $subfolder) = split;
            next if $hash_seen{$hash};

            my $src_subfolder = "$cluster_dir/$subfolder";
            my $dst_subfolder = "$db_dir/$folder_index";
            make_path($dst_subfolder);

            # 複製 .in 與 .sout
            opendir(my $sfh, $src_subfolder) or next;
            while (my $file = readdir($sfh)) {
                next unless $file =~ /\.(in|sout)$/;
                copy("$src_subfolder/$file", "$dst_subfolder/$file") or warn "Copy failed: $!";
            }
            closedir($sfh);

            # 紀錄資訊
            $hash_seen{$hash} = 1;
            push @summary, "$elements $hash $folder_index";
            $folder_index++;
        }
        close $fh;
    }
}

# 輸出總資訊檔
my $info_file = "$db_dir/all_sout_info.txt";
open my $out_fh, ">", $info_file or die "Cannot write to $info_file: $!";
print $out_fh "$_\n" for @summary;
close $out_fh;

# ✅ 刪除暫存資料夾
remove_tree($tmp_dir) if -d $tmp_dir;

print "✅ All unique subfolders collected into: $db_dir\n";
print "📄 Summary saved in: $info_file\n";
