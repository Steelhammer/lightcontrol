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

=head1 lcConfig.pl

Functions to handle the configuration  

=cut

my $configFile = "/etc/lctimer/lightcontrol.conf";

my %userPrefsGlobal = GetConfiguration();

=head2 GetConfiguration()

=over 2

=item * I<parameters: none>

=item * I<returns: hash of config values>

=back

I<Synopsis>

 my %userPrefs = GetConfiguration();
 my $localValue = $userPrefs{'LOGFILE'}

Reads the config file (lightcontrol.conf) to create a hash of the configuration values found in the file.

=cut

sub GetConfiguration
{
  my %config;
  my $confSectionFound = 0;
  
  open(CONFFILE, $configFile) or die("Could not open file!");
  while (my $line = <CONFFILE>)
  {
    if (!$confSectionFound && ($line =~ /START CONFIG/))
    {
      $confSectionFound = 1;
      next;
    }
    next if !$confSectionFound;
    chomp($line);                 # strip newline
    $line =~ s/#.*//;             # ignore comments
    $line =~ s/^\s+//;            # strip leading whitespace
    $line =~ s/\s+$//;            # strip trailing whitespace
    next unless length($line);    # anything left?
    last if ($line eq "END CONFIG");
    
    my ($var, $value) = split(/\s*=\s*/, $line, 2);
    $config{$var} = $value;
  }

  close(CONFFILE);
    
  return %config;
}

=head2 GetDBConnection()

=over 2

=item * I<parameters: none>

=item * I<returns: DBI database handle>

=back

Creates the database handle. 
The handle should be released in the calling function. 
The database file is created if it does not exists. 
The required tables are created if they do not exist.

=cut

sub GetDBConnection
{
  my $dbFileName = $userPrefsGlobal{'LIGHTSDBFILE'};
  my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbFileName", "", "" );
  
  $dbh->do("CREATE TABLE IF NOT EXISTS receivers 
           (
            id INTEGER PRIMARY KEY,
            name TEXT UNIQUE, 
            dimmer BOOLEAN,
            house INTEGER,
            code INTEGER,
            status TEXT,
            learned BOOLEAN
           )"
          );
          
  $dbh->do("CREATE TABLE IF NOT EXISTS timers 
         (
          id INTEGER PRIMARY KEY,
          recid INTEGER, 
          ontime TEXT,
          offtime TEXT,
          days INTEGER,
          onaction INTEGER
         )"
        );
          
  $dbh->{PrintError} = 0;
  
  return $dbh;
}

=head2 GenerateNewReceiverParameters()

=over 2

=item * I<parameters: none>

=item * I<returns: integer array(houseID, unitID)>

=back

I<Synopsis>

 my ($house, $unit) = GenerateNewReceiverParameters();

The next house ID to use is stored in the config file (lightcontrol.conf). 
The unit ID is generated as a random number 0-15. 
The house ID is updated in config file. 

=cut

sub GenerateNewReceiverParameters
{
  my $curHouse = $userPrefsGlobal{'CURRENTRECEIVERCODE'};
  my $newUnit = int(rand(15)); # Only one unit per house to simplify
  my $newHouse = $curHouse+1;
 
  local $/=undef;

  open(CONFFILE, $configFile) or die("Could not open file!");
  my $confFileContent = <CONFFILE>;
  close(CONFFILE);
  
  $confFileContent =~ s/CURRENTRECEIVERCODE = \d+/CURRENTRECEIVERCODE = $newHouse/;
  
  open(CONFFILE, "> $configFile") or die("Could not open file! $!");
  print CONFFILE $confFileContent;
  close(CONFFILE);
  
  return ($curHouse, $newUnit);
}


1;

