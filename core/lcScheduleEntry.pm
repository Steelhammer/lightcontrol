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

=head1 lcScheduleEntry.pm

Object to represent a timer setting in the timer daemon.

I<Synopsis>

 Create Schedule Entry object
 my $entry = new lcScheduleEntry(_id => 5, 
                                 _recId => 2,
                                 _onTime => 'SUNSET',
                                 _offTime => '23:00R30',
                                 _repeatPattern => 56,
                                 _dimLevel => 0
                                );

=cut

use strict;

require "lcConfig.pl";

my %userPrefsGlobal = GetConfiguration();

package lcScheduleEntry;

use DateTime;
use DateTime::Event::Sunrise;

########################################################

=head1 Member functions

Functions to access the schedule object.

=cut

########################################################

=head2 new()

=over 2

=item * I<parameters:>

_id (integer) - ID of the timer

_recId (integer) - ID of the receiver affected

_onTime (string) - Time when the receiver should turn on

_onTime (string) - Time when the receiver should turn off

_repeatPattern (integer) - Days of the week to use the timer

_dimLevel (integer) - Dimmer level to use when activating the timer

=item * I<returns: undef/lcScheduleEntry object>

=back

Constructor to create the lcScheduleEntry object. 
 

=begin html 

For valid parameter formats see <a href="lcCore.html#gettimers__" >GetTimers()</a>

=end html

=cut

sub new
{
  my $invocant = shift;
  my $class   = ref($invocant) || $invocant;

  my $self = {
    _id             => undef,
    _recId          => undef,
    _actionType     => undef,
    _actionTime     => undef,
    _curWeekDay     => undef,
    _onTime         => undef,
    _offTime        => undef,
    _repeatPattern  => undef,
    _dimLevel       => undef,
    @_
  };
  
  bless $self, $class;
  
  if (Init($self))
  {
    return $self;
  }
  else
  {
    return undef;
  }
}

=head2 Init()

=over 2

=item * I<parameters: none>

=item * I<returns: (0/1)>

=back

Uses the input to the constructor L</"new()"> to initiate all parts of the object. 

=cut

sub Init
{
  my ($self) = @_;
  
  my $result = 1;
  
  #TODO check input parameters (even if they are checked before entered into the database...)
  #$self->{_id} 
  #$self->{_recId}
  #$self->{_onTime}
  #$self->{_offTime}
  #$self->{_repeatPattern}
  #$self->{_dimLevel}
  
  my $curTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'});
  $self->{_curWeekDay} = $curTime->day_of_week();
  #First check repeat pattern...
  my $checkDay = $self->{_curWeekDay};
  my $daysFromNow = 0;
  while ($daysFromNow < 8)
  {
    my $found = index($self->{_repeatPattern}, $checkDay);
    last if $found >= 0;
    $checkDay++;
    $daysFromNow++;
    $checkDay = 1 if $checkDay > 7;
  }
  if ($checkDay == $self->{_curWeekDay})
  {
    my $onTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'});
    my $offTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'});
    my $actualOnTime = GetActualTime($self, $self->{_onTime});
    my ($onHour, $OnMinute) = split(/:/, $actualOnTime, 2);
    $onTime->set_hour($onHour);
    $onTime->set_minute($OnMinute);
    $onTime->set_second(0);
    my $actualOffTime = GetActualTime($self, $self->{_offTime});
    my ($offHour, $OffMinute) = split(/:/, $actualOffTime, 2);
    $offTime->set_hour($offHour);
    $offTime->set_minute($OffMinute);
    $offTime->set_second(0);
    if ($offTime < $onTime ) #offTime is smaller than (before) onTime => offTime should be after midnight
    {
      $offTime->add(days => 1);
    }
    
    if (($onTime >= $curTime) || (($onTime < $curTime) && ($offTime > $curTime))) #onTime is AFTER $curTime, i.e. occurs in the future (or NOW)
    {                                                                             #or if onTime is before $curTime but offTime hasn't occured yet
      $self->{_actionType} = 'ON';
      $self->{_actionTime} =  $onTime->clone();
    }
    else # Will result in an extra OFF event if both ON and OFF times are in the past
    {
      $self->{_actionType} = 'OFF';
      $self->{_actionTime} =  $offTime->clone();
      #Call get next event function?
    }
  }
  else
  {
    my $onTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'});
    my $actualOnTime = GetActualTime($self, $self->{_onTime});
    my ($onHour, $OnMinute) = split(/:/, $actualOnTime, 2);
    $onTime->set_hour($onHour);
    $onTime->set_minute($OnMinute);
    $onTime->set_second(0);
    $onTime->add(days => $daysFromNow);
    $self->{_actionType} = 'ON';
    $self->{_actionTime} =  $onTime->clone();
    $self->{_curWeekDay} = $onTime->day_of_week();
  }
  
  return $result;
}

=head2 IsActionTimeDue()

=over 2

=item * I<parameters:>

$compTime (DateTime object) - Time stamp to compare

=item * I<returns: (0/1)>

=back

Check if the timer is due. 
Current time is typically used for $compTime.

=cut

sub IsActionTimeDue
{
  my ($self, $compTime) = @_;
  
  return ($self->{_actionTime} <= $compTime); 
}

=head2 GetReceiverId()

=over 2

=item * I<parameters: none>

=item * I<returns: (integer) receiver ID>

=back

Get the ID of the receiver affected by the timer setting.

=cut

sub GetReceiverId
{
  my ($self) = @_;
  return $self->{_recId};
}

=head2 GetId()

=over 2

=item * I<parameters: none>

=item * I<returns: (integer) timer ID>

=back

Get the ID of the timer setting.

=cut

sub GetId
{
  my ($self) = @_;
  return $self->{_id};
}

=head2 GetNextEvent()

=over 2

=item * I<parameters: none>

=item * I<returns: 1>

=back

Get next action time for the timer setting, based of the state of the object.

=cut

sub GetNextEvent
{
  my ($self) = @_;
  
  if ($self->{_actionType} eq 'ON')
  {
    my $onTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'});
    my $offTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'});
    my $actualOnTime = GetActualTime($self, $self->{_onTime});
    my ($onHour, $OnMinute) = split(/:/, $actualOnTime, 2);
    $onTime->set_hour($onHour);
    $onTime->set_minute($OnMinute);
    $onTime->set_second(0);
    my $actualOffTime = GetActualTime($self, $self->{_offTime});
    my ($offHour, $OffMinute) = split(/:/, $actualOffTime, 2);
    $offTime->set_hour($offHour);
    $offTime->set_minute($OffMinute);
    $offTime->set_second(0);
    if ($offTime < $onTime ) #offTime is smaller than (before) onTime => offTime should be after midnight
    {
      $offTime->add(days => 1);
    }
    $self->{_actionType} = 'OFF';
    $self->{_actionTime} =  $offTime->clone();
    #$self->{_curWeekDay} = $offTime->day_of_week();
  }
  elsif ($self->{_actionType} eq 'OFF')
  {
    my $checkDay = $self->{_curWeekDay}+1;
    $checkDay = 1 if $checkDay > 7;
    my $daysFromNow = 1;
    while ($daysFromNow < 8)
    {
      my $found = index($self->{_repeatPattern}, $checkDay);
      last if $found >= 0;
      $checkDay++;
      $daysFromNow++;
      $checkDay = 1 if $checkDay > 7;
    }
    my $onTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'}); #Wrong day, if off time is after midnight
    my $actualOnTime = GetActualTime($self, $self->{_onTime});
    my ($onHour, $OnMinute) = split(/:/, $actualOnTime, 2);
    $onTime->set_hour($onHour);
    $onTime->set_minute($OnMinute);
    $onTime->set_second(0);
    my $offTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'});
    my $actualOffTime = GetActualTime($self, $self->{_offTime});
    my ($offHour, $OffMinute) = split(/:/, $actualOffTime, 2);
    $offTime->set_hour($offHour);
    $offTime->set_minute($OffMinute);
    $offTime->set_second(0);
    if ($offTime < $onTime ) # if off time is after midnight
    {
      $daysFromNow--; 
    }
    $onTime->add(days => $daysFromNow);
    $self->{_actionType} = 'ON';
    $self->{_actionTime} =  $onTime->clone();
    $self->{_curWeekDay} = $onTime->day_of_week();
  }
  else
  {
    die "Bad schedule item - action type";
  }
  return 1;
}

=head2 GetEventType()

=over 2

=item * I<parameters: none>

=item * I<returns: (string) ON/OFF>

=back

Get the comming event for the timmer setting.

=cut

sub GetEventType
{
  my ($self) = @_;
  
  return $self->{_actionType}
}

=head2 GetDimLevel()

=over 2

=item * I<parameters: none>

=item * I<returns: (integer) dimmer level>

=back

Get the dimmer level to use for the ON action.

=cut

sub GetDimLevel
{
  my ($self) = @_;
  
  return $self->{_dimLevel}
}

=head2 GetActualTime()

=over 2

=item * I<parameters:>

$timeStr (string) - Time stamp

=item * I<returns: (string) absolute time stamp>

=back

=begin html 

Takes the time stamp according to <a href="lcCore.html#gettimers__" >GetTimers()</a> and
translate into a hh:mm time stamp

=end html

=cut

sub GetActualTime
{
  my ($self, $timeStr) = @_;
  
  if ($timeStr =~ /^\d{1,2}:\d{2}$/)
  {
    return $timeStr;
  }
  if ($timeStr =~ /^(\d{1,2}):(\d{2})R(\d+)/)
  {
    my $hour = $1;
    my $minute = $2;
    my $randMinutes = $3;
    my $randomTime = int(rand($randMinutes+1));
    my $actTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'});
    $actTime->set_hour($hour);
    $actTime->set_minute($minute);
    $actTime->set_second(0);
    $actTime->add(minutes => $randomTime);
    my $actualTime = sprintf("%02s:%02s", $actTime->hour(), $actTime->minute());
    
    return $actualTime;
  }
  if ($timeStr =~ /^(SUNRISE|SUNSET)(\+\d+|-\d+){0,1}/)
  {
    my $eventType = $1;
    my $offSet = 0;
    $offSet = $2 if defined($2);
    $offSet =~ s/\+//;
    my $nowTime = DateTime->now(time_zone => $userPrefsGlobal{'TIMEZONE'});
    my $nowyear = $nowTime->year;
    # Workaround for bug in sunrise function, work with a fixed year when calculating the sunrise/sunset at bug date
    if (($nowTime->month == 2) and ($nowTime->day == 21))
    {
      $nowTime->set_year(1993);
    }
    $nowTime->set_hour(0);
    $nowTime->set_minute(0);
    $nowTime->set_second(0);
    #print "$nowyear\n";
    #print "Long: $userPrefsGlobal{'LONGITUDE'}\n";
    #print "Lat : $userPrefsGlobal{'LATITUDE'}\n";
    #print "Now: $nowTime\n";
    my $actTime;
    
    if ($eventType eq 'SUNRISE')
    {
      my $sunrise = DateTime::Event::Sunrise->sunrise (
                                                        longitude => $userPrefsGlobal{'LONGITUDE'},
                                                        latitude  => $userPrefsGlobal{'LATITUDE'},
                                                        altitude  => '-0.833',
                                                        iteration => '1'
                                                      );
      $actTime = $sunrise->next($nowTime);
    }
    elsif ($eventType eq 'SUNSET')
    {
      my $sunset = DateTime::Event::Sunrise->sunset (
                                                      longitude => $userPrefsGlobal{'LONGITUDE'},
                                                      latitude  => $userPrefsGlobal{'LATITUDE'},
                                                      altitude  => '-0.833',
                                                      iteration => '1'
                                                     );
      $actTime = $sunset->next($nowTime);
    }
    else
    {
      die "Bad event type: SUNRISE/SUNSET";
    }
    
    # Workaround for bug in sunrise function, work with a fixed year when calculating the sunrise/sunset
    # After calculation is done reset the year
    if (($nowTime->month == 2) and ($nowTime->day == 21))
    {
      if ($actTime->year > 1993)
      {
        $nowyear++; 
      }
    }
    else
    {
      if ($actTime->year > $nowyear)
      {
        $nowyear++; 
      }
    }
    $nowTime->set_year($nowyear);
    $actTime->add(minutes => $offSet);
    
    my $actualTime = sprintf("%02s:%02s", $actTime->hour(), $actTime->minute());
    
    return $actualTime;
  }
  # we should not end up here...
  return $timeStr;  
}

=head2 _compare_overload()

Sort receivers according to time for next action.

=cut

use overload ( 'fallback' => 1,
               '<=>' => '_compare_overload',
               'cmp' => '_compare_overload',
             );

  
sub _compare_overload
{
  my ($s1, $s2) = @_;
  return $s1->{_actionTime} cmp $s2->{_actionTime};
}


1;
