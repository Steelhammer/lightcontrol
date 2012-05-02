#!/usr/bin/perl

=pod

   _ _       _     _                  _             _   
  | (_) __ _| |__ | |_ ___ ___  _ __ | |_ _ __ ___ | |  
  | | |/ _` | '_ \| __/ __/ _ \| '_ \| __| '__/ _ \| |  
  | | | (_| | | | | || (_| (_) | | | | |_| | | (_) | |  
  |_|_|\__, |_| |_|\__\___\___/|_| |_|\__|_|  \___/|_|  
       |___/                                            

  lightcontrol - Light control using the Tellstick
  Copyright (C) 2012  Fredrik Stalhammar

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
    
  Inspired by the works of http://www.telldus.se/

  https://github.com/Steelhammer/lightcontrol

=cut

=head1 lcReceiver.pm

Object to represent the receiver.

I<Synopsis>

 Create receiver object
 my $receiver = new lcReceiver(_id=>123, _name=>'Some Name', _house=>123456, _code=>7, _dimmer=>1);
 
 Handle the receiver
 
 Turn the receiver on
 $receiver->ReceiverActivate();
 
 Turn the receiver off
 $receiver->ReceiverDeactivate();
 
 Dim the receiver
 $receiver->ReceiverDim(7);
 
 Register the receiver HW
 $receiver->ReceiverLearn();

=cut


use strict;
#use tsCmdcore;

require "lcConfig.pl";

my %userPrefsGlobal = GetConfiguration();

package lcReceiver;
use Device::SerialPort;
use Time::HiRes qw( usleep);

my $statusFile = "/etc/tstimer/recstatus";
my $statusFileTemp = "/etc/tstimer/recstatus-temp";

########################################################

=head1 Member functions

Functions to access the receiver object.

=cut

########################################################

=head2 new()

=over 2

=item * I<parameters:>

_id (integer) - ID of the receiver

_name (string) - Recevier name

_house (integer) - House code

_code (integer) - Unit code

_dimmer (0/1) - Is the receiver a dimmer

=item * I<returns: undef/lcReceiver object>

=back

Constructor to create the lcReceiver object.

=cut

sub new
{
  my $invocant = shift;
  my $class   = ref($invocant) || $invocant;

  my $self = {
    _id         => undef,
    _name       => undef,
    _house      => undef,
    _code       => undef,
    _dimmer     => undef,
    @_
  };
  
  bless $self, $class;
  
  if (defined($self->{_id}) && defined($self->{_name}) && defined($self->{_house}) && defined($self->{_code}) && defined($self->{_dimmer}) )
  {
    return $self;
  }
  else
  {
    return undef; 
  }
}

=head2 ReceiverName()

=over 2

=item * I<parameters:>

$name (string) - Optional, Change the receiver name to this. 

=item * I<returns: (string) Receiver name>

=back

Get/Set the receiver name. If the name parameter is set, the name is updated. 
In either case the name of the recevier is returned.

=cut

sub ReceiverName
{
  my ($self, $name) = @_;
  
  if (defined($name))
  {
    $self->{_name} = $name;
  }
  
  return $self->{_name};
}

=head2 ReceiverId()

=over 2

=item * I<parameters: none>

=item * I<returns: (integer) receiver id>

=back

Get the receiver id. There is no in parameter as the receiver id should not be changed.

=cut

sub ReceiverId
{
  my ($self) = @_;
  
  return $self->{_id};
}

=head2 ReceiverHouse()

=over 2

=item * I<parameters: none>

=item * I<returns: (integer) receiver house id>

=back

Get the receiver house id. There is no in parameter as the receiver house id should not be changed.

=cut

sub ReceiverHouse
{
  my ($self) = @_;
  
  return $self->{_house};
}

=head2 ReceiverCode()

=over 2

=item * I<parameters: none>

=item * I<returns: (integer) receiver unit id>

=back

Get the receiver unit id. There is no in parameter as the receiver unit id should not be changed.

=cut

sub ReceiverCode
{
  my ($self) = @_;
  
  return $self->{_code};
}

=head2 ReceiverIsDimmer()

=over 2

=item * I<parameters:>

$isDimmer (0/1) - Optional, receiver is dimmer. 

=item * I<returns: (0/1)>

=back

Get/Set the receiver dimmer status. 
If the $isDimmer parameter is set, the dimmer status is updated. 
In either case the dimmer status is returned.

=cut

sub ReceiverIsDimmer
{
  my ($self, $isDimmer) = @_;
  
  if (defined($isDimmer))
  {
    $self->{_dimmer} = $isDimmer;
  }
  
  return $self->{_dimmer};
}

=head2 ReceiverActivate()

=over 2

=item * I<parameters: none>

=item * I<returns: (0/1)>

=back

Activate the receiver. If the receiver is a dimmer, this command will set the dimmer to max.

=cut

sub ReceiverActivate
{
  my ($self) = @_;
  
  my $result = turnOn($self->{_house}, $self->{_code}, $self->{_dimmer}, $self->{_id});
  
  return $result;
}

=head2 ReceiverDeactivate()

=over 2

=item * I<parameters: none>

=item * I<returns: (0/1)>

=back

Deactivate the receiver.

=cut

sub ReceiverDeactivate
{
  my ($self) = @_;
  
  my $result = turnOff($self->{_house}, $self->{_code}, $self->{_id});
  
  return $result;
}

=head2 ReceiverDim()

=over 2

=item * I<parameters:>

$level (integer) - Dimming level

=item * I<returns: (0/1)>

=back

Set the dimmer level, 0-15. 
No action will be taken if the receiver is not a dimmer.

=cut

sub ReceiverDim
{
  my ($self, $level) = @_;
  
  if (!$self->{_dimmer})
  {
    #print "NOT DIMMER!!!";
    return 0;
  }
  
  my $result = dim($self->{_house}, $self->{_code}, $level, $self->{_id});
  
  
  return $result;
}

=head2 ReceiverLearn()

=over 2

=item * I<parameters: none>

=item * I<returns: (0/1)>

=back

Send the learn command to connect to the receiver HW.

=cut

sub ReceiverLearn
{
  my ($self) = @_;
  
  my $result = learn($self->{_house}, $self->{_code}, $self->{_id});

  return $result;
}

=head2 _compare_overload()

Sort receivers according to receiver name.

=cut

use overload ( 'fallback' => 1,
               '<=>' => '_compare_overload',
               'cmp' => '_compare_overload',
             );

  
sub _compare_overload
{
  my ($s1, $s2) = @_;
  return $s1->{_name} cmp $s2->{_name};
}

########################################################

=head1 Support functions

Functions to perform tasks for the lcReceiver object.

=cut

########################################################

=head2 turnOn()

=over 2

=item * I<parameters:>

$house (integer) - House code

$code (integer) - Unit code

$isDimmer (0/1) - Is the receiver a dimmer

$id (integer) - ID of the receiver

=item * I<returns: 0/1>

=back

Generate and send the Turn on command. 
If the receiver is a dimmer, call L</"dim()"> to set max dim level

=cut

sub turnOn
{
  my ($house, $code, $isDimmer, $id) = @_;
  
  if ($isDimmer)
  {
    return dim($house, $code, 15, $id);
  }
  else
  {
    my $cmdStr = ord('R').",5,";
    $cmdStr .= CreateNEXASelfLearnCommand($house, $code, 0, 15);
    
    my @sendAr = split(',', $cmdStr);
    my $rawStr = "";
    for (my $i=0; $i < scalar(@sendAr); $i++)
    {
      $rawStr .= chr($sendAr[$i]);
    }
    my $result = SendCommand($rawStr);
    if ($result)
    {
      my $dbh = main::GetDBConnection();
      $dbh->do("UPDATE receivers SET status='On' WHERE id=$id");
      my $timeNow = time();
      $dbh->do("INSERT OR IGNORE INTO statusupdate (name, time) values ('status', $timeNow)");
      $dbh->do("UPDATE statusupdate SET time = $timeNow WHERE name='status'");
      undef($dbh);
    }
    return $result;
  }
}

=head2 turnOff()

=over 2

=item * I<parameters:>

$house (integer) - House code

$code (integer) - Unit code

$id (integer) - ID of the receiver

=item * I<returns: 0/1>

=back

Generate and send the Turn off command. 

=cut

sub turnOff
{
  my ($house, $code, $id) = @_;
  
  my $cmdStr = ord('R').",5,";
  $cmdStr .= CreateNEXASelfLearnCommand($house, $code, 0, 0);
  
  my @sendAr = split(',', $cmdStr);
  my $rawStr = "";
  for (my $i=0; $i < scalar(@sendAr); $i++)
  {
    $rawStr .= chr($sendAr[$i]);
  }
  
  my $result = SendCommand($rawStr);
  if ($result)
  {
    my $dbh = main::GetDBConnection();
    $dbh->do("UPDATE receivers SET status='Off' WHERE id=$id");
    my $timeNow = time();
    $dbh->do("INSERT OR IGNORE INTO statusupdate (name, time) values ('status', $timeNow)");
    $dbh->do("UPDATE statusupdate SET time = $timeNow WHERE name='status'");

    undef($dbh);
  }
  return $result
}

=head2 dim()

=over 2

=item * I<parameters:>

$house (integer) - House code

$code (integer) - Unit code

$level (integer) - Dimming level

$id (integer) - ID of the receiver

=item * I<returns: 0/1>

=back

Generate and send the Dimming command. 
If $level == 0 call L</"turnOff()"> to deactivate the receiver.
If $level == 15 the receiver status will be set to 'On'.

=cut

sub dim
{
  my ($house, $code, $level, $id) = @_;
  
  if ($level == 0)
  {
    turnOff($house, $code, $id);
  }
  else
  {  
    my $cmdStr = ord('R').",5,";
    $cmdStr .= CreateNEXASelfLearnCommand($house, $code, 1, $level);
    
    my @sendAr = split(',', $cmdStr);
    my $rawStr = "";
    for (my $i=0; $i < scalar(@sendAr); $i++)
    {
      $rawStr .= chr($sendAr[$i]);
    }
    
    my $result = SendCommand($rawStr);
    if ($result)
    {
      my $dbh = main::GetDBConnection();
      if ($level<15)
      {
        $dbh->do("UPDATE receivers SET status='Dimmed: $level' WHERE id=$id");
      }
      else
      {
        $dbh->do("UPDATE receivers SET status='On' WHERE id=$id");
      }
      my $timeNow = time();
      $dbh->do("INSERT OR IGNORE INTO statusupdate (name, time) values ('status', $timeNow)");
      $dbh->do("UPDATE statusupdate SET time = $timeNow WHERE name='status'");
      undef($dbh);
    }
    
    return $result;
  }
}

=head2 learn()

=over 2

=item * I<parameters:>

$house (integer) - House code

$code (integer) - Unit code

$id (integer) - ID of the receiver

=item * I<returns: 0/1>

=back

Generate and send the learn commad.

=cut

sub learn
{
  my ($house, $code, $id) = @_;
 
  my $cmdStr = ord('R').",5,";
  $cmdStr .= CreateNEXASelfLearnCommand($house, $code, 0, 15);
  
  my @sendAr = split(',', $cmdStr);
  my $rawStr = "";
  for (my $i=0; $i < scalar(@sendAr); $i++)
  {
    $rawStr .= chr($sendAr[$i]);
  }
  my $result = SendCommand($rawStr);
  if ($result)
  {
    my $dbh = main::GetDBConnection();
    $dbh->do("UPDATE receivers SET learned=1 WHERE id=$id");
    my $timeNow = time();
    $dbh->do("INSERT OR IGNORE INTO statusupdate (name, time) values ('settings', $timeNow)");
    $dbh->do("UPDATE statusupdate SET time = $timeNow WHERE name='settings'");
    undef($dbh);
  }
  return $result;
}

=head2 CreateNEXASelfLearnCommand()

=over 2

=item * I<parameters:>

$house (integer) - House code

$code (integer) - Unit code

$dim (integer) - Dimming command requested

$level (integer) - Dimming level

=item * I<returns: (string) NEXA command string>

=back

Generate the command string based on the input.
This function is used by L</"turnOn()">, L</"turnOff()">, L</"dim()"> and L</"learn()">.

=cut

sub CreateNEXASelfLearnCommand
{
  my ($house, $code, $dim, $level) = @_;

  my $sendStr = ord('T').",127,255,24,1";
  my $nbrpulse = $dim ? 147 : 132;
  $sendStr.= ",$nbrpulse";
  
  my $m = "";
  
  #House
  for (my $i = 25; $i >= 0; --$i)
  {
    my $hbin = ($house & 1 << $i) ? "10" : "01"; 
		$m .= $hbin;
	}
	
	#Group
	$m .= "01";
	
	#On/Off/Dim
	if ($dim)
	{
		$m .= "00";
	}
	elsif ($level == 0)
	{
		$m .= "01";
	}
	else
	{
		$m .= "10";
	}
	
	#Code
	for (my $i = 3; $i >= 0; --$i)
  {
    my $cbin = $code & 1 << $i ? "10" : "01";
		$m .= $cbin;
	}
	
	if ($dim)
	{
		for (my $i = 3; $i >= 0; --$i)
		{
		  my $dbin = $level & 1 << $i ? "10" : "01";
			$m .= $dbin;
		}
	}
	
	#Need even number of characters, adding one.
	$m .= "0";
	
	my @binAr = split(//, $m);
	
	my $encode = 9; #b1001, startcode
	for (my $i = 0; $i < scalar(@binAr); ++$i)
	{
		$encode <<= 4;
		my $v = 0;
		if ($binAr[$i] == '1') {
			$encode |= 8; #b1000
		} else {
			$encode |= 10; #b1010;
		}
		if ($i % 2 == 0) {
		  $sendStr.= ",$encode";
			$encode = 0;
		}
	}
	$sendStr.= ",".ord('+');

  return $sendStr;
}

=head2 SendCommand()

=over 2

=item * I<parameters:>

$id (string) - Device command string

=item * I<returns: (integer) 0/1>

=back

Write the device command string to the tellstick.

=cut

sub SendCommand
{
  my ($cmdStr) = @_;
  
  my $retVal = 0;
  my $quiet; #Dummy variable to conform with Win32 serial port
  # $device = '/dev/tellstick';
  my $PortObj = new Device::SerialPort ($userPrefsGlobal{'TELLSTICK'}, $quiet);
  #     || die "Can't open $device: $!\n";
  
  if ($PortObj)
  {
    $PortObj->baudrate(4800);
    $PortObj->parity("none");
    $PortObj->databits(8);
    $PortObj->stopbits(1);
    
    my  $count_out = $PortObj->write($cmdStr);

    usleep(600000);
    $PortObj->close; # || warn "close failed";
    $retVal = 1; 
  }
  return $retVal;
}

1;
