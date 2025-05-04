#!/usr/bin/perl
=b

=cut

#-----perl-----
use strict;
use warnings;

#get current for the corresponding setting    
my $ip = `/usr/sbin/ip a`;    
$ip =~ /1\d\d\.11\d\.\d+\.(\d+)/;
my $cluster = $1;
$cluster =~ s/^\s+|\s+$//;
print "\$cluster: $cluster\n";

my $Subject = "Cluster $cluster Problem Report(Do not reply!)";
my @temp = @ARGV;
map { s/^\s+|\s+$//g; } @temp;
my $temp = join("\\n",@temp);
my $body = "To whom it may concern,\\n\\nThe following happens to Cluster $cluster:\\n$temp";
#-----python paremeters-----
my $file = "recipient.txt";
my @emails;
# Open the file and read email addresses
open my $fh, '<', $file or die "Cannot open $file: $!";
while (<$fh>) {
    chomp;  # Remove trailing newline character
    next if /^#/;  # Skip lines starting with "#"
    s/^\s+|\s+$//g;  # Trim leading/trailing spaces
    next unless $_;  # Skip empty lines
    push @emails, "\"$_\"";  # Add quotes around each email
}
close $fh;

# Convert the array to a formatted string
# Wrap each email in quotes before joining
my $recipient_email = join(",", map { qq($_) } @emails);

#my $recipient_email = join(",", @emails);
print "recipient_email: $recipient_email\n";
my $sender_email = 'jushinpon01@gmail.com';

my $smtp_password = `head -n 1 ./smtp_pass.txt`;
chomp $smtp_password;
my $output_python_filename='mail.py';

#-----here doc-----
my %mail_para = (
            sender_email => $sender_email,
            recipient_email => $recipient_email,
            smtp_password => $smtp_password,
            Subject => $Subject,
            output_file => $output_python_filename,
            body => $body
            );
&mail(\%mail_para);

sub mail
{
my ($mail_hr) = @_;
my $mail = <<"END_MESSAGE";
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import pathlib

# Set up the email sender and recipient
sender_email = "$mail_hr->{sender_email}"
recipient_email = [$mail_hr->{recipient_email}]

# Set up the message content
message = MIMEMultipart()
message["From"] = sender_email
message["To"] = ", ".join(recipient_email)
message["Subject"] = "$mail_hr->{Subject}"

# Set up the SMTP server
smtp_server = "smtp.gmail.com"
smtp_port = 587
smtp_username = sender_email
smtp_password = "$mail_hr->{smtp_password}"
body = "$mail_hr->{body}"
message.attach(MIMEText(body, "plain"))

# Send the email
with smtplib.SMTP(smtp_server, smtp_port) as server:
    server.starttls()
    server.login(smtp_username, smtp_password)
    text = message.as_string()
    server.sendmail(sender_email, recipient_email, text)
    print("Email sent successfully!")

END_MESSAGE

    open(FH, '>', $mail_hr->{output_file}) or die $!;
    print FH $mail;
    close(FH);
    sleep(1);
    my $py_response = `python $mail_hr->{output_file}`;
    chomp $py_response;
    print "$py_response\n";
}

