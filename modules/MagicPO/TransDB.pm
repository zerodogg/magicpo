#!/usr/bin/perl
# MagicPO::TransDB
# Copyright (C) Eskild Hustvedt 2008
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package MagicPO::TransDB;
use strict;
use warnings;
use constant { 
	# These make prettier code
	true => 1, false => 0 
};
use Carp;
use MagicPO::Parser;
our $VERSION;
$VERSION = 0.4;

# Purpose: Create a new object
# Usage: $obj = MagicPO::TransDB->new(dictionary.mdb, progressionCallback,NoLastTranslator);
#	dictionary.mdb is the path to the dictionary file to use. If this file
#		does not exist then an empty one will be created.
#	progressionCallback is a coderef to the function to call every time
#		something has progressed. Can be undef.
#	NoLastTranslator is a boolean, if true then MagicPO::Parser will not update
#		Last-Translator.
sub new
{
	my $this = shift;
	$this = {};
	$this->{dict} = shift;
	$this->{progressionCallback} = shift;
	$this->{NoLastTranslator} = shift;
	$this->_loadDict();
	bless($this,'MagicPO::TransDB');
	return $this;
}

# Purpose: Translate a file using the DB
# Usage: changed = obj->translate(file.po);
#	changed is an int, the number of strings changed
sub translate
{
	my $this = shift;
	my $targetfile = shift;
	my $changed = 0;
	# Load the PO-file
	my $poFile = MagicPO::Parser->new($targetfile,$this->{progressionCallback},$this->{NoLastTranslator});
	if(not $poFile)
	{
		die("\n");
	}
	foreach my $lookup(keys(%{$poFile->{PoFile}}))
	{
		progressed();
		next if $lookup == 1;
		# Make sure it isn't translated already.
		if (not $poFile->{PoFile}{$lookup}{'magicpo-statusflags'}{'fuzzy'})
		{
			my $skip;
			foreach my $ent (%{$poFile->{PoFile}{$lookup}})
			{
				next if not $ent =~ /^msgstr/;
				if (length($poFile->{PoFile}{$lookup}{$ent}))
				{
					$skip = true;
					last;
				}
			}
			next if $skip;
		}
		my $msgid = $poFile->{PoFile}{$lookup}{msgid};
		if(not defined($msgid))
		{
			die("Uh oh, entry $lookup doesn't have an msgid. Corrupt. Refusing to go on.\n");
		}
		my $dblookup = $this->{dbPo}->{Lookup}{$msgid};
		if(not defined($dblookup))
		{
			next;
		}
		my $translated = false;
		# Translate
		foreach my $ent (keys (%{$poFile->{PoFile}{$lookup}}))
		{
			next if not $ent =~ /^msgstr/;
			if (not length($poFile->{PoFile}{$lookup}{$ent}))
			{
				if (defined($dblookup))
				{
					if(defined($this->{dbPo}->{PoFile}{$lookup}{$ent}))
					{
						$poFile->{PoFile}{$lookup}{$ent} = $this->{dbPo}->{PoFile}{$dblookup}{$ent};
						$poFile->markdirty($lookup);
						delete($poFile->{PoFile}{$lookup}{'magicpo-statusflags'}{'fuzzy'});
						$translated = true;
					}
				}
			}
		}
		if ($translated)
		{
			$changed++;
		}
	}
	$poFile->write($targetfile);
	return($changed);
}

# Purpose: Add a PO-file to the translation database
# Usage: obj->addpo(file.po);
sub addpo
{
	my $this = shift;
	my $file = shift;
	# Load the PO-file
	my $poFile = MagicPO::Parser->new($file,\&progressed,$this->{NoLastTranslator});
	if(not $poFile)
	{
		die("\n");
	}
	foreach my $lookup(keys(%{$poFile->{PoFile}}))
	{
		progressed();
		next if $lookup == 1;
		# Ignore fuzzy strings
		if ($poFile->{PoFile}{$lookup}{'magicpo-statusflags'}{'fuzzy'})
		{
			next;
		}

		my $msgid = $poFile->{PoFile}{$lookup}{msgid};
		if(not defined($msgid))
		{
			print "Uh oh, entry $lookup doesn't have an msgid. This is probably a corrupt PO-file\n";
			print "or a bug in the parser. Dumping parsed information and bailing out:\n";
			eval('use Data::Dumper;');
			print Dumper($poFile->{PoFile}{$lookup});
			die("\n");
		}
		# Attempt to remove translation credits
		if ($poFile->{PoFile}{$lookup}{msgid} =~ /(translator-credits|THE NAMES OF THE TRANSLATORS)/i)
		{
			next;
		}
		# Ignore dupes
		if (defined($this->{dbPo}->{Lookup}{$msgid}))
		{
			next;
		}
		# Alter comments and status flags (clear both)
		my $fromFile = $file;
		$fromFile =~ s#^/(home|users)/[^/]+/?##;
		my $comment = "# From $fromFile\n# Read at ".scalar(localtime());
		$poFile->{PoFile}{$lookup}{'magicpo-comments'} = $comment;
		$poFile->{PoFile}{$lookup}{'magicpo-rawcomments'} = "\n".$comment;
		$poFile->{PoFile}{$lookup}{'magicpo-statusflags'} = {};
		# Make sure there's a TRANSLATION in there. If either of the msgstr's
		# are EMPTY, then ignore it
		my $skip = false;
		foreach my $ent (%{$poFile->{PoFile}{$lookup}})
		{
			next if not $ent =~ /^msgstr/;
			if (not length($poFile->{PoFile}{$lookup}{$ent}))
			{
				$skip = true;
				last;
			}
		}
		next if $skip;
		# Ignore msgctxt
		delete($poFile->{PoFile}{$lookup}{'msgctxt'});
		# Drop magicpo-raw
		delete($poFile->{PoFile}{$lookup}{'magicpo-raw'});
		# Okay, We're good, add it
		$this->{dbPo}->addstring($poFile->{PoFile}{$lookup});
	}
	return true;
}

# Purpose: Write the DB
# Usage: obj->writeDb(file?);
#	file can be undef, in which case it will write it back
#	to the source file.
sub writeDb
{
	my $this = shift;
	my $file = shift;
	return $this->{dbPo}->write($file);
}

# Purpose: Internal progression indicator. Calls progression callback if
# 	available
# Usage: this->_progressed();
sub _progressed
{
	my $this = shift;
	if(not $this->{progressionCallback})
	{
		return true;
	}
	$this->{progressionCallback}->();
	return true;
}

# Purpose: Load the dictionary
# Usage: this->_loadDict();
sub _loadDict
{
	my $this = shift;

	if (not -e $this->{dict})
	{
		open(my $targetf, '>',$this->{dict}) or die("Unable to create file: $this->{dict}: $!\n");
		print $targetf "# MagicPO translation database\n";
		print $targetf 'msgid ""'."\n";
		print $targetf 'msgstr ""'."\n";
		print $targetf '"MIME-Version: 1.0\n"'."\n";
		print $targetf '"Content-Type: text/plain; charset=UTF-8\n"'."\n";
		print $targetf '"Content-Transfer-Encoding: 8bit\n"'."\n";
		print $targetf '"X-Generator: MagicPO\n"'."\n";
		print $targetf '"X-PO-Type: MagicPO translation database\n"'."\n";
		close($targetf) or warn("Failed to close filehandle for $this->{dict} (bad stuff might happen): $!\n");
	}

	$this->{dbPo} = MagicPO::Parser->new($this->{dict},$this->{progressionCallback},$this->{NoLastTranslator});
	return true;
}
1;
