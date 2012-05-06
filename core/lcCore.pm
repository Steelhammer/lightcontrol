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

=head1 lcCore.pm

Shared functions between lccmd and lctimerd.pl

=cut

use strict;
use DateTime;
use IPC::ShareLite;
use File::ReadBackwards;
require "lcConfig.pl";
use lcReceiver;
use DBI;

my %userPrefsGlobal = GetConfiguration();

my $share = IPC::ShareLite->new(
    -key     => $userPrefsGlobal{'SHAREDKEY'},
    -create  => 'yes',
    -destroy => 'no'
) or die $!;

########################################################

=head1 Receiver functions

Functions to manipulate the recceivers.

=cut

########################################################

=head2 GetReceiversRaw()

=over 2

=item * I<parameters:>

$onerec (integer) - ID of receiver to get information for.

=item * I<returns: List of receiver(s)/FAIL>

 Format:
 ID<tab>Name<tab>House code<tab>Unit code<tab>Dimmer<tab>Status<tab>Learned<new line>
 
 ID         : ID for the receiver
 Name       : Name describing the receiver, e.g Kitchen - Window
 House code : (internal) Part 1 of the auto generated code to identify the receiver HW 
 Unit code  : (internal) Part 2 ...
 Dimmer     : 0/1 - The receiver can be dimmed
 Status     : Off/On/Dimmed n - 1<=n<=14
 Learned    : 0/1 - The receiver is connected atleast one HW

=back

List the receiver settings. All receivers are returned if the ID parameter is 0.

=cut

sub GetReceiversRaw
{
  my ($oneRec) = @_;
  my $receivers;

  my $dbh = GetDBConnection();
  
  my $getOneRec;
  if ($oneRec > 0)
  {
    $getOneRec = "WHERE id=$oneRec";
  }
  my $query = "SELECT id, name, house, code, dimmer, status, learned FROM receivers $getOneRec ORDER BY name";
  my $query_handle = $dbh->prepare($query);
  $query_handle->execute();
  
  $query_handle->bind_columns(\my($id, $name, $house, $code, $dimmer, $status, $learned));
  while($query_handle->fetch())
  {
    $receivers .= "$id\t$name\t$house\t$code\t$dimmer\t$status\t$learned\n";
  }
    
  $query_handle->finish;
  undef($dbh);
  
  if ($receivers eq "")
  {
    $receivers = "FAIL - No receiver found\n";
  }
  
  return $receivers;
}

=head2 GetReceiversById()

=over 2

=item * I<parameters: none>

=item * I<returns: List of lcReceiver objects>

=back

The lcReceiver objects are placed in a hash with the reciever ID as key.

=cut


sub GetReceiversById
{
  my %receivers;
  
  my $dbh = GetDBConnection();
  
  my $query = "SELECT id, name, house, code, dimmer, status, learned FROM receivers ORDER BY id";
  my $query_handle = $dbh->prepare($query);
  $query_handle->execute();
  
  $query_handle->bind_columns(\my($id, $name, $house, $code, $dimmer, $status, $learned));
  while($query_handle->fetch())
  {
     $receivers{$id} = new lcReceiver(_id=>$id, _name=>$name, _house=>$house, _code=>$code, _dimmer=>$dimmer);
  }
    
  $query_handle->finish;
  undef($dbh);
    
  return %receivers;
}

=head2 AddReceiver()

=over 2

=item * I<parameters:>

$receiverName (string) - Descriptive name for the receiver, e.g. Kitchen - Window

$isDimmer (0/1) - The receiver can be dimmed

=item * I<returns: (integer) 0/ID of the created receiver>

 A non zero return value means that the receiver was created successfully.

=back

Creating new settings for a receiver. 
The name of the receiver must be unique. 
The HW parameters are automatically generated from the seed in the config file (lightcontrol.conf).

=cut

sub AddReceiver
{
  my ($receiverName, $isDimmer) = @_;

  my $recType = $isDimmer ? "dimmer" : "receiver";
  my $status = 0;
  my ($house, $code) = GenerateNewReceiverParameters();
  
  my $dbh = GetDBConnection();  
  $dbh->do("INSERT INTO receivers (name, dimmer, house, code, status, learned) VALUES ('$receiverName', $isDimmer, $house, $code, 'Off', 0)");

  if (!$dbh->err())
  {
    PrintToLog("Adding $recType: $receiverName");
    $share->store( "Update" );
    $status = $dbh->func('last_insert_rowid');
    UpdateSettingsTime();
  }
  undef($dbh);
  
  return $status;
}

=head2 UpdateReceiver()

=over 2

=item * I<parameters:>

$id (integer)- ID of the receiver to update

$receiverName (string) - Descriptive name for the receiver, e.g. Kitchen - Window

$isDimmer (0/1) - The receiver can be dimmed

=item * I<returns: (integer) 0/ID of the updated receiver>

 A non zero return value means that the receiver was updated successfully.

=back

Updating the settings for a receiver.
The name of the receiver must be unique. 
The HW parameters cannot be changed.

=cut

sub UpdateReceiver
{
  my ($id, $receiverName, $isDimmer) = @_;

  my $recType = $isDimmer ? "dimmer" : "receiver";
  my $status = 0;
  
  my $dbh = GetDBConnection();  
  $dbh->do("UPDATE receivers SET name='$receiverName', dimmer=$isDimmer WHERE id=$id");
  
  if (!$dbh->err())
  {
    PrintToLog("Updating $recType: $receiverName");
    $share->store( "Update" );
    $status = 1;
    UpdateSettingsTime();
  }
  undef($dbh);
  
  return $status;
}

=head2 DeleteReceiver()

=over 2

=item * I<parameters:>

$id (integer) - ID of the receiver to delete

=item * I<returns: (integer) 0/ID of the deleted receiver>

=back

Deleting a receiver.

=cut

sub DeleteReceiver
{
  my ($id) = @_;
  my $status = 0;
  
  my $dbh = GetDBConnection(); 
  my ($receiverName, $isDimmer) = $dbh->selectrow_array("SELECT name, dimmer FROM receivers WHERE id=$id");
  
  if (defined($receiverName))
  {
    my $recType = $isDimmer ? "dimmer" : "receiver";
          
    $dbh->do("DELETE FROM receivers WHERE id=$id");
    
    if (!$dbh->err())
    {
      PrintToLog("Deleting $recType: $receiverName");
      $dbh->do("DELETE FROM timers WHERE recid=$id");
      $share->store( "Update" );
      $status = $id;
      UpdateSettingsTime();
    }
  }
  undef($dbh);
  
  return $status;
}

=head2 GetReceiverStatus()

=over 2

=item * I<parameters:>

$onerec (integer) - ID of receiver to get information for.

=item * I<returns: (string) List of receiver status>

 Format:
 ID<tab>Status<new line>
 
 ID         : ID for the receiver
 Status     : Off/On/Dimmed n - 1<=n<=14

=back

List the receiver status. All receivers status are returned if the ID parameter is 0.

=cut

sub GetReceiverStatus
{
  my ($oneRec) = @_;
  my $receivers;

  my $dbh = GetDBConnection();
  
  my $getOneRec = "";
  
  if ($oneRec > 0)
  {
    $getOneRec = "WHERE id=$oneRec";
  }
  my $query = "SELECT id, status FROM receivers $getOneRec ORDER BY id";
  my $query_handle = $dbh->prepare($query);
  $query_handle->execute();
  
  $query_handle->bind_columns(\my($id, $status));
  while($query_handle->fetch())
  {
    $receivers .= "$id\t$status\n";
  }
    
  $query_handle->finish;
  undef($dbh);
  
  if ($receivers eq "")
  {
    $receivers = "FAIL - No receiver found\n";
  }
  
  return $receivers;
}

=head2 ReceiverExists()

=over 2

=item * I<parameters:>

$id (integer) - ID of the receiver to check 

=item * I<returns: 0/1>

=back

Check if a receiver with id $id exists in the database.

=cut

sub ReceiverExists
{
  my ($id) = @_;
  
  my $recExist = 0;
  my $dbh = GetDBConnection();  

  my ($nbrRec) = $dbh->selectrow_array("SELECT COUNT(*) FROM receivers WHERE id=$id");

  if (!$dbh->err())
  {
    $recExist = $nbrRec;
  }
  undef($dbh);
  
  return $recExist;
}

=head2 ResetReceiverStatus()

=over 2

=item * I<parameters: none>

=item * I<returns: 0/1>

=back

Turns off all receivers and re-initiate the timers.

I.e. sync up the status of all receivers, the system cannot track if a manual remote is used. 

=cut

sub ResetReceiverStatus
{
  my %receivers = GetReceiversById();
  my $result = 1;
  
  foreach my $key (keys %receivers)
  {
    if (!$receivers{$key}->ReceiverDeactivate())
    {
      $result = 0;
    }
  }
  if ($result)
  {
    PrintToLog("Resetting all receivers");
    $share->store( "Update" );
  }
  return $result;
}

=head2 InitReceiverResetTimer()

=over 2

=item * I<parameters: none>

=item * I<returns: (string ) hh:mm time stamp>

=back

Sets the timer for the reset fuctionality based of the RESETTIME setting in the config file. 
This functionality has the added benefit of ensuring that no light are left on by misstake. 
If the timer is set to a time just after you normally leave home in the morning, you can be sure all lights are off 
(unless set by a timer).

=cut

sub InitReceiverResetTimer
{
  my $curTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'});
  my $resetTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'});
  
  my ($resetHour, $resetMinute) = split(/:/, $userPrefsGlobal{'RESETTIME'}, 2);
  
  $resetTime->set_hour($resetHour);
  $resetTime->set_minute($resetMinute);
  $resetTime->set_second(0);
  
  if ($resetTime < $curTime)
  {
    $resetTime->add(days => 1);
  }
  
  return $resetTime;
}

########################################################

=head1 Timer functions

Functions to manipulate the timer settings.

=cut

########################################################

=head2 GetTimers()

=over 2

=item * I<parameters:>

$onerec (integer) - ID of receiver to get timer information for.

=item * I<returns: (string) List of timer(s)/FAIL>

 Format:
 ID<tab>Receiver ID<tab>On time<tab>Off time<tab>Days<tab>Dim level<new line>
 
 ID          : ID for the timer
 Receiver ID : ID of the receiver connected to the timer
 On Time     : Time to turn on the receiver
               hh:mm[Rmmm] - hour:minute +RANDOM minutes. E.g. 19:30R30 = 19:31 - 20:00
               SUNRISE|SUNSET[+-mmm] - Sunrise/Sunset +- minutes E.g. SUNSET-20
 Off Time    : Time to turn off the receiver
               See 'On Time'
 Days        : Days of the week the timer is active
               E.g. 1234567 - all days, 567 - Fr, Sa, Su
 Dim level   : Dimmer level to use when activating the timer 
               0      : No dimming, turn on full.
               1 - 15 : Level to use

=back

List the timer settings. All timers are returned if the Receiver ID parameter is 0.

=cut

sub GetTimers
{
  my ($oneRec) = @_;
  my $timers = "";

  my $dbh = GetDBConnection();
  
  my $getTimersOneRec = "";
  
  if ($oneRec > 0)
  {
    $getTimersOneRec = "WHERE recid=$oneRec";
  }

  my $query = "SELECT id, recid, ontime, offtime, days, onaction FROM timers $getTimersOneRec ORDER BY id";
  my $query_handle = $dbh->prepare($query);
  $query_handle->execute();
  
  $query_handle->bind_columns(\my($id, $recid, $ontime, $offtime, $days, $dimlevel));
  while($query_handle->fetch())
  {
    $timers .= "$id\t$recid\t$ontime\t$offtime\t$days\t$dimlevel\n";
  }
    
  $query_handle->finish;
  undef($dbh);
  
  if ($timers eq "")
  {
    $timers = "FAIL - No timers found\n";
  }
  
  return $timers;
}

=head2 AddNewTimer()

=over 2

=item * I<parameters:>

$receiverId (integer) - ID of the receiver for which to set the timer

$onTime (string) - Time to turn on receiver

$offTime (string) - Time to turn off the receiver

$repDays (integer) - Days of the week to use the timer

$dimLevel (integer) - Use this dimmer level when activating the receiver

=item * I<returns: (integer) 0/ID of the created timer setting>

=back

Add a new timer to the requested receiver. 
$dimlevel will we set to 0 for non dimmable receivers. 
See L</"GetTimers()"> for information about the formats for the parameters. 

=cut

sub AddNewTimer
{
  my ($receiverId, $onTime, $offTime, $repDays, $dimLevel) = @_;
  
  my $result = 0;
  
  if ($receiverId ne "" && $onTime ne "" && $onTime ne ":" && $offTime ne "" && $offTime ne ":" && $repDays ne "" && $dimLevel>=0 && $dimLevel<=15)
  {
    my %receivers = GetReceiversById();
    if (defined ($receivers{$receiverId}))
    {
      if (!$receivers{$receiverId}->ReceiverIsDimmer())
      {
        $dimLevel = 0;
      }
      my $dbh = GetDBConnection();  
      $dbh->do("INSERT INTO timers (recid, ontime, offtime, days, onaction) VALUES ($receiverId, '$onTime', '$offTime', $repDays, $dimLevel)");

      if (!$dbh->err())
      {
        my $receiverName = $receivers{$receiverId}->ReceiverName();
        PrintToLog("Adding new timer to receiver '$receiverName'");
        $share->store( "Update" );
        $result = $dbh->func('last_insert_rowid');
        UpdateSettingsTime();
      }
      undef($dbh);
    }  
  }
  return $result;
}

=head2 EditTimer()

=over 2

=item * I<parameters:>

$timerId (integer) - ID of the timer to update

$onTime (string) - Time to turn on receiver

$offTime (string) - Time to turn off the receiver

$repDays (integer) - Days of the week to use the timer

$dimLevel (integer) - Use this dimmer level when activating the receiver

=item * I<returns: (integer) 0/ID of the updated timer setting>

=back

Edit the settings for a timer
The receiver affected by the setting cannot be changed. 
$dimlevel will we set to 0 for non dimmable receivers. 
See L</"GetTimers()"> for information about the formats for the parameters. 

=cut

sub EditTimer
{
  my ($timerId, $onTime, $offTime, $repDays, $dimLevel) = @_;
  
  my $result = 0;
  
  if ($timerId ne "" && $onTime ne "" && $onTime ne ":" && $offTime ne "" && $offTime ne ":" && $repDays ne "" && $dimLevel>=0 && $dimLevel<=15)
  {
    my $dbh = GetDBConnection();
    my ($receiverId) = $dbh->selectrow_array("SELECT recid FROM timers WHERE id=$timerId");
    
    if (!$dbh->err())
    {
      my %receivers = GetReceiversById();
      if (defined ($receivers{$receiverId}))
      {
        if (!$receivers{$receiverId}->ReceiverIsDimmer())
        {
          $dimLevel = 0;
        }

        $dbh->do("UPDATE timers SET ontime='$onTime', offtime='$offTime', days=$repDays, onaction=$dimLevel WHERE id=$timerId");

        if (!$dbh->err())
        {
          my $receiverName = $receivers{$receiverId}->ReceiverName();
          PrintToLog("Updating timer to receiver '$receiverName'");
          $share->store( "Update" );
          $result = $timerId;
          UpdateSettingsTime();
        }
        
      }
    }  
    undef($dbh);
  }
    
  return $result;
}

=head2 DeleteTimer()

=over 2

=item * I<parameters:>

$id (integer) - ID of the timer to delete

=item * I<returns: (integer) 0/ID of the deleted timer>

=back

Deleting a timer.

=cut

sub DeleteTimer
{
  my ($id) = @_;
  my $status = 0;
  
  my $dbh = GetDBConnection(); 
  my ($receiverId) = $dbh->selectrow_array("SELECT recid FROM timers WHERE id=$id");
  
  if (defined($receiverId))
  {          
    $dbh->do("DELETE FROM timers WHERE id=$id");
    
    if (!$dbh->err())
    {
      my ($receiverName) = $dbh->selectrow_array("SELECT name FROM receivers WHERE id=$receiverId");
      if ($dbh->err())
      {
        $receiverName = "Unknown";
      }
      PrintToLog("Deleting timer from '$receiverName'");
      $share->store( "Update" );
      $status = $id;
      UpdateSettingsTime();
    }
  }
  undef($dbh);  
  
  return $status;
}

=head2 GetTimerShedule()

=over 2

=item * I<parameters: None>

=item * I<returns: list of lcScheduleEntry objects>

=back

Read the timer settings from the database and generate a list of objects to represent them.

=cut

sub GetTimerShedule
{  
  my @shedItem;
  my $i = 0;
  
  my $dbh = GetDBConnection();
  my $query = "SELECT id, recid, ontime, offtime, days, onaction FROM timers ORDER BY id";
  my $query_handle = $dbh->prepare($query);
  $query_handle->execute();
  $query_handle->bind_columns(\my($id, $recid, $ontime, $offtime, $days, $dimlevel));
  
  while($query_handle->fetch())
  {    
    $shedItem[$i++] = new lcScheduleEntry(_id => $id, 
                                          _recId => $recid,
                                          _onTime => $ontime,
                                          _offTime => $offtime,
                                          _repeatPattern => $days,
                                          _dimLevel => $dimlevel
                                         );
  }
    
  $query_handle->finish;
  undef($dbh);  
  
  @shedItem = sort @shedItem;
    
  return @shedItem;
}

=head2 TimerExists()

=over 2

=item * I<parameters:>

$id (integer) - ID of the timer to check 

=item * I<returns: 0/1>

=back

Check if a timer with id $id exists in the database.

=cut

sub TimerExists
{
  my ($id) = @_;
  
  my $timExist = 0;
  my $dbh = GetDBConnection();  

  my ($nbrTim) = $dbh->selectrow_array("SELECT COUNT(*) FROM timers WHERE id=$id");

  if (!$dbh->err())
  {
    $timExist = $nbrTim;
  }
  undef($dbh);
  
  return $timExist;
}

########################################################

=head1 Common functions

Functions perform common and supporting tasks.

=cut

########################################################

=head2 GetLog()

=over 2

=item * I<parameters:>

$nbrEntries (integer) - Number of log lines to display 

=item * I<returns: The last $nbrEntries lines of the log>

=back

Diplays the log as plain text. 
The log is presented with last entry first. 
If $nbrEntries = 0 the last 10 lines will be returned.

=cut

sub GetLog
{
  my ($nbrEntries) = @_;
  my $bw = File::ReadBackwards->new($userPrefsGlobal{'LOGFILE'});
  my $i = 0;
  my $result = "";
  
  while((defined(my $log_line = $bw->readline)) and ($i<$nbrEntries))
  {
    $result .= $log_line;
    $i++;
  }
  $bw->close();

  return $result;
}

=head2 PrintToLog()

=over 2

=item * I<parameters:>

$logStr (string) - Text to print to the log 

=item * I<returns: 0/1>

=back

Print an entry to the application log. 
Time stamp and new line will be added automatically. 

=cut

sub PrintToLog
{
  my ($logStr) = @_;
    
  my $currentTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'});
  my $timeStr = $currentTime->ymd." ".$currentTime->hms;
  $logStr = $timeStr." ".$logStr."\n";
  open(LOGFILE, ">> $userPrefsGlobal{'LOGFILE'}") or die("Could not open file!");
  print LOGFILE $logStr;
  close(LOGFILE);
  
  return 1;
}

=head2 CheckForStatusUpdate()

=over 2

=item * I<parameters:>

$checkTime (integer) - UNIX timestamp to compare update time with. 

=item * I<returns: Status updated/Settings updated/No update>

=back

Check database for last update of status and settings.
Compare the update time to  $checkTime, return the update information.
If both status and settings are updated, 'Settings updated' will be returned.

=cut

sub CheckForStatusUpdate
{
  my ($checkTime) = @_;
  
  my $result = "";
  
  my $dbh = GetDBConnection();
  my $query = "SELECT name, time FROM statusupdate";
  my $query_handle = $dbh->prepare($query);
  $query_handle->execute();
  $query_handle->bind_columns(\my($name, $updatetime));
  
  my $settingsUpdateTime = undef;
  my $statusUpdateTime = undef;
  
  while($query_handle->fetch())
  {
    #print "$name, $updatetime\n";
    if ($name eq "settings")
    {
      $settingsUpdateTime = $updatetime;
    }
    elsif ($name eq "status")
    {
      $statusUpdateTime = $updatetime;
    } 
  }
  $query_handle->finish;
  undef($dbh);
  
  if (defined($settingsUpdateTime) and defined($statusUpdateTime))
  {
    if ($settingsUpdateTime > $checkTime)
    {
      $result = "Settings updated";
    }
    elsif ($statusUpdateTime > $checkTime)
    {
      $result = "Status updated";
    }
    else
    {
      $result = "No update";
    } 
  }
  
  
  
  return $result;
}

=head2 UpdateSettingsTime()

=over 2

=item * I<parameters: None>

=item * I<returns: Nothing>

=back

Set the settings update time to current time.

=cut

sub UpdateSettingsTime
{  
  my $dbh = GetDBConnection();
  my $timeNow = time();
  $dbh->do("INSERT OR IGNORE INTO statusupdate (name, time) values ('settings', $timeNow)");
  $dbh->do("UPDATE statusupdate SET time = $timeNow WHERE name='settings'");
  undef($dbh);
}


1;
