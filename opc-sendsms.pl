#!/usr/bin/perl -w 

=head1 TITLE

opc-sendsms.pl

=head1 SYNOPSIS

C<opc-sendsms.pl> I<14 opc notification arguments>

=head1 DESCRIPTION

This program is designed to be a notification script for HP Operations Manager.

That is, you configure this script to run
as one of the choices in

 Node -> Utilities -> Notification Service

C<opc-sendsms.pl> reads a file to determine who to SMS, and then sends 
it through the ValueSMS gateway, which is an Australian SMS provider.

Currently
C<opc-sendsms.pl> doesn't support authenticating proxies, and MS-ISA is 
only supported
through something like cntlm.

=head1 CONFIGURATION

C<opc-sendsms.pl> looks for a file called C<opc-sendsms.cfg> in its working
directory. This file has English-looking sentences such as:

 When the MESSAGE GROUP is SECURITY notify Paul Jones.
 If the MESSAGE GROUP is OpC sms Sandra Smith.
 if severity is critical contact herman manager
 Paul Jones' mobile is 0412 123 456.
 SANDRA SMITH: 0412-987-543
 herman manager is 0412444555

The valid keywords in the first kind of sentence are:

=over 4

=item Message number

=item Hostname

=item Operating system

=item Date received on managed node

=item Time received on managed node

=item Date received on management server

=item Time received on management server

=item Application

=item Message group

=item Object

=item Severity

=item Operators

=item Message text

=item Instructions

=item Custom Message Attributes

=item Number of duplicates

=back

=head1 TO-DO

It would be nice to be able to define teams, and their schedules. I don't
think this will be very difficult to add.


=head1 VERSION

$Id: opc-sendsms.pl 297 2010-09-01 07:24:18Z gregb $

=cut

use strict;

my $proxy = undef;
my $sms_username = undef;
my $sms_password = undef;

use URI;
use LWP::UserAgent;

my @parameter_names = 
("Message number", "Hostname", "Operating system", 
"Date received on managed node", "Time received on managed node",
"Date received on management server", "Time received on management server",
"Application","Message group","Object","Severity","Operators",
"Message text","Instructions","Custom Message Attributes",
"Number of duplicates");

my %phonenums = ();

my %who_to_send_to;

open(CONFIG,"opc-sendsms.cfg") || die "Can't read opc-sendsms.cfg";
my $previous_line = "";
CONFIG_LINE:
while (<CONFIG>) {
 chomp;
 s/#.*$//;
 s/--.*$//;
 s/\s*$//;
 $_ = $previous_line . " " . $_;
 if (/\\\s*$/) { $previous_line = $_; next; } else { $previous_line = ""; }
 if (/^\s*$/) { next CONFIG_LINE; }
 if (/^\s*(if|when)\s*(the|)\s*(.*)\s*(call|contact|notify|sms)\s*(.*)\.?$/i) {
   my $conditions = $3;
   my $recipient = uc $5;
   $recipient =~ s/\s*\.\s*//;
   my (@conditions) = split(/\s*and\s*/,$conditions);
   my $condition;
   foreach $condition (@conditions) {
     my $i;
     PARAMETER_NAME:
     for($i=0;$i<=$#parameter_names;$i++) {
       my $param = $parameter_names[$i];
       my $val = $ARGV[$i];
       next PARAMETER_NAME
             unless $condition =~ /\s*${param}\s*(is|contains|matches)\s*(.*)\s*/i;
       my $requirement = $2;
       my $operator = $1;
       $requirement =~ s/^\*//;
       $requirement =~ s/\s*$//;
       $val =~ s/^\s*//;
       $val =~ s/\s*$//;
       next CONFIG_LINE if ($operator =~ /is/i and uc($val) ne uc($requirement) ) ; 
       next CONFIG_LINE unless ($val =~ /$requirement/i);
     }
   }
   # Bingo. Condition matches
   my @recipients = split(/\s*(,|\band\b)\s*/,uc $recipient);
   my $username;
   OPERATOR:
   foreach $username (@recipients) {
      $who_to_send_to{$username} = 1;
   }
   next CONFIG_LINE;
 }
 if (/\s*(.*)\s*(:|=|'s? number|'s? mobile|'s? handphone|'s? phone number|'s? phonenumber)\s*(is|)\s*([0-9 -]+)\.?\s*$/i) {
    my $username = uc $1;
    my $phonenumber = $4;
    $phonenumber =~ s/ //g;
    $phonenums{$username} = $phonenumber;
    next CONFIG_LINE;
 }
 if (/\s*(the|)\s*(valuesms|sms|)\s*username\s*(:|=|is)\s*(.*)\s*$/i) {
    $sms_username = $4; 
    next CONFIG_LINE;
 }
 if (/\s*(the|)\s*(valuesms|sms|)\s*password\s*(:|=|is)\s*(.*)\s*$/i) {
    $sms_password = $4; 
    next CONFIG_LINE;
 }
 die "Cannot understand $_";
}



# Check for phone number uniqueness.
my @phonenums;
my $phone_owner;
foreach $phone_owner (keys %who_to_send_to) {
 unless (exists $phonenums{$phone_owner}) {
   print STDERR "Supposed to notify $phone_owner, but no phone number on record.\n";
   next;
 }
 push(@phonenums,$phonenums{$phone_owner}); 
}

my $phonenum = join(",",@phonenums);
my $message = "\U$ARGV[10]\E $ARGV[12] Node: $ARGV[1] App: $ARGV[7] Obj: $ARGV[9] ".
 ($ARGV[13] =~ /^\s*$/ ? " " : "Instr: $ARGV[13] ") .
 ($ARGV[14] =~ /^\s*$/ ? "" : "CMA: $ARGV[14]") ;


print "Phones = $phonenum\nMessage = $message\n";

exit 0 unless $phonenum =~ /\d/; # got to be at least one digit.

die "Must specify ValueSMS username and password in opc-sendsms.cfg" unless
 defined $sms_username and defined $sms_password; 

my $url = URI->new('http://www.valuesms.com/msg.php');
$url->query_form(
  'u' => $sms_username,
  'p' => $sms_password,
  'd' => $phonenum,
  'm' => $message
);

my $ua = LWP::UserAgent->new;  
$ua->timeout(10);
$ua->proxy('http',$proxy) if defined $proxy;

my $response = $ua->get($url);

die "$url error: ", $response->status_line unless $response->is_success;


