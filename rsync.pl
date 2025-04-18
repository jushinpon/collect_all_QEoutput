#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use POSIX qw(strftime);
use Time::HiRes qw(sleep);

# === 設定 ===
my $source_dir   = "/home/jsp1/QEoutput_database/";
my $target_dir   = "/home/gdrive_mount/QEoutput_database/";
my $log_dir      = "/home/jsp1/rsync_logs";
my $timeout_secs = 28800;  # 8 小時
my $max_retries  = 3;
my $retry_delay  = 30;     # 秒

# === 建立 log 目錄（若不存在）===
unless (-d $log_dir) {
    print "📁 建立 log 目錄: $log_dir\n";
    make_path($log_dir) or die "❌ 無法建立 log 目錄: $!";
}

# === 清除 30 天前的 log ===
print "🧹 清除 30 天前的舊 log...\n";
system("find $log_dir -type f -name '*.log' -mtime +30 -exec rm -f {} \\;");

# === 檢查來源與目的地 ===
die "❌ 來源資料夾不存在: $source_dir\n" unless -d $source_dir;
die "❌ 掛載目的地不存在: $target_dir\n" unless -d $target_dir;

# === 執行 rsync + 自動重試 ===
my $timestamp = strftime("%Y%m%d_%H%M%S", localtime);
my $log_file = "$log_dir/rsync_$timestamp.log";

print "🚀 開始備份資料：$source_dir → $target_dir\n";
print "📄 log file: $log_file\n";

my $attempt = 0;
my $success = 0;

while ($attempt < $max_retries && !$success) {
    $attempt++;
    my $try_time = strftime("%Y-%m-%d %H:%M:%S", localtime);
    print "🔁 第 $attempt 次嘗試 ($try_time)...\n";

    my $cmd = "timeout $timeout_secs rsync -av --progress --inplace --append --partial " .
              "\"$source_dir\" \"$target_dir\" 2>&1 | tee -a \"$log_file\"";

    my $status = system($cmd);

    if ($status == 0) {
        print "✅ 傳輸成功！\n";
        $success = 1;
    } else {
        warn "⚠️ 傳輸失敗（exit code: $status, signal: " . ($status & 127) . ", code: " . ($status >> 8) . ")\n";
        if ($attempt < $max_retries) {
            print "⏳ 等待 $retry_delay 秒後重試...\n";
            sleep($retry_delay);
        } else {
            print "❌ 已達最大重試次數，備份失敗！請查看 $log_file 進一步除錯。\n";
        }
    }
}

print "📌 完成時間：" . strftime("%Y-%m-%d %H:%M:%S", localtime) . "\n";
