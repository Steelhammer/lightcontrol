#!/bin/bash

pod2html --htmlroot=doc --infile=../core/lcCore.pm --outfile=lcCore.html --podpath=..:./core --podroot=.. --recurse --title="lcCore.pm"
pod2html --htmlroot=doc --infile=../core/lcConfig.pl --outfile=lcConfig.html --podpath=..:./core --podroot=.. --recurse --title="lcConfig.pl"
pod2html --htmlroot=doc --infile=../core/lcReceiver.pm --outfile=lcReceiver.html --podpath=..:./core --podroot=.. --recurse --title="lcReceiver.pm"
pod2html --htmlroot=doc --infile=../core/lcScheduleEntry.pm --outfile=lcScheduleEntry.html --podpath=..:./core --podroot=.. --recurse --title="lcScheduleEntry.pm"
pod2html --htmlroot=doc --infile=../lctimerd.pl --outfile=lctimerd.html --podpath=..:./core --podroot=.. --recurse --title="lctimerd.pl"
pod2html --htmlroot=doc --infile=../lccmd --outfile=lccmd.html --podpath=..:./core --podroot=.. --recurse --title="lccmd"

rm ./*.tmp