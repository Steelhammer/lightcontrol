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

=head1 lctimerd.pl

Timer daemon for the light controller.

=cut

use strict;
use DateTime;
use IPC::ShareLite;
use Time::HiRes qw ( time sleep );

#/usr/share/perl5

require "lcCore.pm";
use lcScheduleEntry;

my %userPrefs = GetConfiguration();

=head2 Shared variable

The shared variable is used to communicate with lccmd. 
The key is set in the configuration file, SHAREDKEY. 
Write 'Update' to this variable when changing receivers or timers. 
This will cause the timer daemon to re-read the configuration.

=cut

my $share = IPC::ShareLite->new(
    -key     => $userPrefs{'SHAREDKEY'},
    -create  => 'yes',
    -destroy => 'yes'
) or die $!;

PrintToLog("Timer: Start");

my %receivers = GetReceiversById();
my @sheduleList = GetTimerShedule();
my $resetTime = InitReceiverResetTimer();

PrintToLog("Timer: Init done");

$SIG{INT} = \&ExitTimerLoop;

=head2 Main timer loop

Checking the schedule item list, over and over...

=cut

while (1)
{
  my $currentTime = DateTime->now(time_zone => $userPrefs{'TIMEZONE'});
  if ($currentTime >= $resetTime)
  {
    ResetReceiverStatus();
    PrintToLog("Timer: Resetting receiver status");
    $resetTime->add(days => 1);
  }
  my $str = $share->fetch;
  if ($str ne "")
  {
    $share->store( "" );
    PrintToLog("Timer: Settings changed, updating");
    %userPrefs = GetConfiguration();
    %receivers = GetReceiversById();
    @sheduleList = GetTimerShedule();
  }
  
  my $t1 = time();
  foreach my $shedItem (@sheduleList)
  {
    last if !$shedItem->IsActionTimeDue($currentTime);

    TimerTakeAction($shedItem);
    $shedItem->GetNextEvent();
  }
  @sheduleList = sort @sheduleList;
  my $t2 = time();
  #print "Sleep time: ", $userPrefs{'TIMERRESOLUTION'} - ($t2 - $t1),"\n";
  sleep ($userPrefs{'TIMERRESOLUTION'} - ($t2 - $t1));
}

print "This will never happen... ;-)\n";


=head2 TimerTakeAction()

=over 2

=item * I<parameters:>

$curItem (lcScheduleEntry object) - Object that need action

=item * I<returns: (integer) 1>

=back

Called when a timer has reached the action time. 
The action to take is determined by the state of the object. 
A lcScheduleEntry object always contain an 'On' AND an 'Off' action. 
The 'On' action can produce a dim command, if the dimlevel > 0 and the affected receiver is a dimmer.

=cut

sub TimerTakeAction
{
  my ($curItem) = @_;
  
  my $log = "Timer: '".$receivers{$curItem->GetReceiverId()}->ReceiverName()."' - ";

  if ($curItem->GetEventType() eq 'ON')
  {
    if (($curItem->GetDimLevel() > 0) and $receivers{$curItem->GetReceiverId()}->ReceiverIsDimmer())
    {
      $receivers{$curItem->GetReceiverId()}->ReceiverDim($curItem->GetDimLevel());
      $log .= "Dimmed: ".$curItem->GetDimLevel();
    }
    else
    {
      $receivers{$curItem->GetReceiverId()}->ReceiverActivate();
      $log .= $curItem->{_actionType};
    }
  }
  elsif ($curItem->GetEventType() eq 'OFF')
  {
    $receivers{$curItem->GetReceiverId()}->ReceiverDeactivate();
    $log .= $curItem->{_actionType};
  }
  else
  {
    die "Bad event type";
  }
  PrintToLog($log);
  return 1;
}

=head2 ExitTimerLoop()

=over 2

=item * I<parameters: none>

=item * I<returns: N/A>

=back

Kills the application, called when Ctrl-c is sent.

=cut

sub ExitTimerLoop
{
   PrintToLog("Timer: Shutting down");
   exit(0);
}
