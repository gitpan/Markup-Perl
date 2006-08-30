package Markup::Perl; # $Id: Perl.pm,v 1.1.1.1 2006/08/29 23:49:47 michael Exp $
our $VERSION = '0.4';

use strict;
use CGI;
use CGI::Carp qw(fatalsToBrowser set_message);
use Filter::Simple;
use base 'Exporter'; our @EXPORT = qw(param header cookie src);
my %headers = (-type=>'text/html', -cookie=>[], -charset=>'UTF-8'); # defaults
my $output = '';

BEGIN {
	{	package Buffer;
		sub TIEHANDLE { my ($class, $buf) = @_; bless $buf => $class;              }
		sub PRINT	  { my $buf = shift; $$buf .= join '', @_;                     }
		sub PRINTF	  { my $buf = shift; my $fm = shift; $$buf .= sprintf($fm, @_);}
	} tie *STDOUT=>"Buffer", \$output;
	
	set_message(sub{
		(my $message = shift) =~ s!\n!<br />!g;
		$output = qq{\n\n<p style="font:14px arial;border:1px dotted #966;padding:10px">
		<b>Sorry, but there was an error:</b><br />$message</p>};
	});
}

sub transform {
	$_ = shift;
	s!<perl\s+src\s*=\s*((["']).+?\2)\s*/>!<perl>src($1)</perl>!gsi;
	s!(.*?)(<perl>(.*?)</perl>)?!print q\x03$1\x03;$3;\n!gsi;
	return $_;
}

FILTER { $_ = transform $_ };

sub param  { my ($v) = @_; return wantarray? @{[CGI::param($v)]} : CGI::param($v) }
sub header { my ($n, $v) = @_; $headers{"-$n"} = $v }
sub cookie {
	(@_ == 1)?
		  return CGI::cookie(shift)
		: push @{$headers{-cookie}}, CGI::cookie(map{$_=>shift} qw(-name -value -expires -path -domain -secure));
}
#sub escapeHTML { return CGI::escapeHTML(shift) }
sub src {
	my $path = shift || return;
	(open SRC, "<$path" and flock(SRC, 1))  or croak qq(Can't open source "$path": $!);
	binmode(SRC, ':utf8' );
	eval transform do{ local $/; <SRC> }; $@ and croak qq(Can't eval source "$path": $@); 
	close SRC;
}

END {
	{no warnings 'untie'; untie *STDOUT;}
	use bytes ();
	binmode(STDOUT, ':utf8');
	print CGI::header(%headers, 'Content-length'=>bytes::length $output), $output;
}

1;
__END__
=head1 NAME

Markup::Perl - turn your CGI inside-out

=head1 SYNOPSIS

    # don't write this...
    print "<html>\n<body>\n";
    print "<h1>", join(', ', 1..10), "</h1>";
    print "</body>\n</html>\n";
    
    # write this instead...
    use Markup::Perl;
    <html>
    <body>
    <h1><perl> print join(', ', 1..10) </perl></h1>
    </body>
    </html>

=head1 DESCRIPTION

I wrote this because, for some problems, particularly in the presentation layer, thinking of the program as a webpage that can run perl is more natural than thinking of it as a perl script that can print a webpage.

It's been tried before, but with the use of Filter::Simple (standard in recent distributions), solutions that are leaner, easier and more flexible are now possible. The source code is compact, very compact: less than 2k of code. And simply put: if you can do it in Perl, you can do it in Markup::Perl, only without all the print statements, heredocs and quotation marks.

=head1 SYNTAX

=over 3

=item basic

It's a perl script when it starts. But as soon as the following line is encountered the rules all change.

  use Markup::Perl;

Every line after that follows this new rule: Anything inside <perl>...</perl> tags will be executed as perl. Anything not inside <perl>...</perl> tags will be printed as is.

So this...

  use Markup::Perl;
  <body>
    Today's date is <perl> print scalar(localtime) </perl>
  </body>

Is functionally equivalent to...

  print "<body>\n";
  print "Today's date is ";
  print scalar(localtime), "\n";
  print "</body>";
  
If you bear that in mind, you can see that this is also possible...

  use Markup::Perl;
  <body>
    <perl> for (1..10) { </perl>
    <b>snap!</b>
    <perl> } </perl>
  </body>

Naturally, anything you can do in an ordinary perl script you can also do inside <perl></perl> tags. Use your favourite CPAN modules, define your own, whatever.

=item outsourcing

If you would like to have a some shared Markup::Perl code in a separate file, simply "include" it like so...

  use Markup::Perl;
  <body>
    Today's date is <perl src='inc/dateview.pml' />
  </body>

The included file can have the same mixture of literal text and <perl> tags allowed in the first file, and can even include other Markup::Perl files using its own <perl src='...' /> tags. Lexical C<my> variables defined in src files are independent of and inaccessible to code in the original file. Package variables are accessible across src files by using the variable's full package name.

=item print order

Not all output happens in a stream-like way, but rather there is an attempt to be slightly intelligent by reordering certain things, such as printing of HTTP headers (including cookies). Thus you can use the C<header()> command anywhere in your code, or even conditionally, but the actual header, if you do print it, will always be output at the start of your document.

=back

=head1 FUNCTIONS

=over 3

=item header(name=>'value')

Adds the given name/value pair to the HTTP header. This can be called from anywhere in your Markup::Perl document.

=item param

Equivalent to CGI::param. Returns the GET or POST value with the given name.

=item cookie

Given a single string argument, returns the value of any cookie by that name, otherwise sets a cookie with the following values from @_: (name, value, expires, path, domain, secure).

=item src('filename')

Transforms the content of the given file to allow mixed literal text and executable <perl>...</perl> code, and evals that content. This function does the same thing as <perl src='filename' /> but can be used within a perl block.

=back

=head1 CAVEATS

For the sake of speed and simplicity, I've left some areas of the code less than bullet-proof. However, if you simply avoid the following bullets, this won't be a problem:

=over 3

=item tags that aren't tags

The parser is blunt. It simply looks for <perl> and </perl> tags, regardless of whether or not you meant them to be treated like tags or not. For example printing a literal </perl> tag requires special treatment. You must write it in such a way that it doesn't B<look> like </perl>. This is the same as printing a "</script>" tag from within a JavaScript block.

  &lt;perl>
  <perl>
  print '<'.'/perl>';
  </perl>

=item including yourself

It is possible to include and run Markup::Perl code from other files using the C<src> function. This will lead to a recursive loop if a file included in such a way also includes a file which then includes itself. This is the same as using the Perl C<do 'file.pl'> function in such a way, and it's left to the programmer to avoid doing this.

=item use utf8

I've made every effort to write code that is UTF-8 friendly. So much so that you are likely to experience more problems for B<not> using UTF-8. Be warned though, if you know you have non-ASCII characters in your documents, which is still "source code" afterall, perl requires you to declare this like so:

  use utf8;
  use Markup::Perl;

Also, saving your documents as UTF-8 (no BOM) is recommended; other settings may or may not work. Files included via the C<src> function are B<always> assumed to be UTF-8.

=back

=head1 COPYRIGHT

The author does not claim copyright on any part of this code; unless otherwise licensed, code in this work should be considered Public Domain.

=head1 AUTHORS

Michael Mathews <micmath@gmail.com>, inspired by !WAHa.06x36 <paracelsus@gmail.com>.

=cut