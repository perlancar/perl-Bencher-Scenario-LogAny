use 5.008001;
use strict;
use warnings;

package Log::Any;

# ABSTRACT: Bringing loggers and listeners together
our $VERSION = '1.040';

use Log::Any::Manager;
use Log::Any::Adapter::Util qw(
  require_dynamic
  detection_aliases
  detection_methods
  log_level_aliases
  logging_aliases
  logging_and_detection_methods
  logging_methods
);

# This is overridden in Log::Any::Test
our $OverrideDefaultAdapterClass;
our $OverrideDefaultProxyClass;

# singleton and accessor
{
    my $manager = Log::Any::Manager->new();
    sub _manager { return $manager }
}

sub import {
    my $class  = shift;
    my $caller = caller();

    my @export_params = ( $caller, @_ );
    $class->_export_to_caller(@export_params);
}

sub _export_to_caller {
    my $class  = shift;
    my $caller = shift;

    # Parse parameters passed to 'use Log::Any'
    my $saw_log_param;
    my @params;
    while ( my $param = shift @_ ) {
        if ( $param eq '$log' ) {
            $saw_log_param = 1;    # defer until later
            next;                  # singular
        }
        else {
            push @params, $param, shift @_;    # pairwise
        }
    }

    unless ( @params % 2 == 0 ) {
        require Carp;
        Carp::croak("Argument list not balanced: @params");
    }

    # get logger if one was requested
    if ($saw_log_param) {
        no strict 'refs';
        my $proxy = $class->get_logger( category => $caller, @params );
        my $varname = "$caller\::log";
        *$varname = \$proxy;
    }
}

sub get_logger {
    my ( $class, %params ) = @_;
    no warnings 'once';

    my $proxy_class = $class->_get_proxy_class( delete $params{proxy_class} );
    my $category =
      defined $params{category} ? delete $params{'category'} : caller;

    if ( my $default = delete $params{'default_adapter'} ) {
        $class->_manager->set_default( $category, $default );
    }

    my $adapter = $class->_manager->get_adapter( $category );

    require_dynamic($proxy_class);
    return $proxy_class->new(
        %params, adapter => $adapter, category => $category,
    );
}

sub _get_proxy_class {
    my ( $self, $proxy_name ) = @_;
    return $Log::Any::OverrideDefaultProxyClass
      if $Log::Any::OverrideDefaultProxyClass;
    return "Log::Any::Proxy" unless $proxy_name;
    my $proxy_class = (
          substr( $proxy_name, 0, 1 ) eq '+'
        ? substr( $proxy_name, 1 )
        : "Log::Any::Proxy::$proxy_name"
    );
    return $proxy_class;
}

# For backward compatibility
sub set_adapter {
    my $class = shift;
    Log::Any->_manager->set(@_);
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Log::Any - Bringing loggers and listeners together

=head1 VERSION

version 1.040

=head1 SYNOPSIS

In a CPAN or other module:

    package Foo;
    use Log::Any qw($log);

    # log a string
    $log->error("an error occurred");

    # log a string and data using a formatting filter
    $log->debugf("arguments are: %s", \@_);

In a Moo/Moose-based module:

    package Foo;
    use Log::Any ();
    use Moo;

    has log => (
        is => 'ro',
        default => sub { Log::Any->get_logger },
    );

In your application:

    use Foo;
    use Log::Any::Adapter;

    # Send all logs to Log::Log4perl
    Log::Any::Adapter->set('Log4perl');

    # Send all logs to Log::Dispatch
    my $log = Log::Dispatch->new(outputs => [[ ... ]]);
    Log::Any::Adapter->set( 'Dispatch', dispatcher => $log );

    # See Log::Any::Adapter documentation for more options

=head1 DESCRIPTION

C<Log::Any> provides a standard log production API for modules.
L<Log::Any::Adapter> allows applications to choose the mechanism for log
consumption, whether screen, file or another logging mechanism like
L<Log::Dispatch> or L<Log::Log4perl>.

Many modules have something interesting to say. Unfortunately there is no
standard way for them to say it - some output to STDERR, others to C<warn>,
others to custom file logs. And there is no standard way to get a module to
start talking - sometimes you must call a uniquely named method, other times
set a package variable.

This being Perl, there are many logging mechanisms available on CPAN.  Each has
their pros and cons. Unfortunately, the existence of so many mechanisms makes
it difficult for a CPAN author to commit his/her users to one of them. This may
be why many CPAN modules invent their own logging or choose not to log at all.

To untangle this situation, we must separate the two parts of a logging API.
The first, I<log production>, includes methods to output logs (like
C<$log-E<gt>debug>) and methods to inspect whether a log level is activated
(like C<$log-E<gt>is_debug>). This is generally all that CPAN modules care
about. The second, I<log consumption>, includes a way to configure where
logging goes (a file, the screen, etc.) and the code to send it there. This
choice generally belongs to the application.

A CPAN module uses C<Log::Any> to get a log producer object.  An application,
in turn, may choose one or more logging mechanisms via L<Log::Any::Adapter>, or
none at all.

C<Log::Any> has a very tiny footprint and no dependencies beyond Perl 5.8.1,
which makes it appropriate for even small CPAN modules to use. It defaults to
'null' logging activity, so a module can safely log without worrying about
whether the application has chosen (or will ever choose) a logging mechanism.

See L<http://www.openswartz.com/2007/09/06/standard-logging-api/> for the
original post proposing this module.

=head1 LOG LEVELS

C<Log::Any> supports the following log levels and aliases, which is meant to be
inclusive of the major logging packages:

     trace
     debug
     info (inform)
     notice
     warning (warn)
     error (err)
     critical (crit, fatal)
     alert
     emergency

Levels are translated as appropriate to the underlying logging mechanism. For
example, log4perl only has six levels, so we translate 'notice' to 'info' and
the top three levels to 'fatal'.  See the documentation of an adapter class
for specifics.

=head1 CATEGORIES

Every logger has a category, generally the name of the class that asked for the
logger. Some logging mechanisms, like log4perl, can direct logs to different
places depending on category.

=head1 PRODUCING LOGS (FOR MODULES)

=head2 Getting a logger

The most convenient way to get a logger in your module is:

    use Log::Any qw($log);

This creates a package variable I<$log> and assigns it to the logger for the
current package. It is equivalent to

    our $log = Log::Any->get_logger;

In general, to get a logger for a specified category:

    my $log = Log::Any->get_logger(category => $category)

If no category is specified, the calling package is used.

A logger object is an instance of L<Log::Any::Proxy>, which passes
on messages to the L<Log::Any::Adapter> handling its category.

If the C<proxy_class> argument is passed, an alternative to
L<Log::Any::Proxy> (such as a subclass) will be instantiated and returned
instead.  The argument is automatically prepended with "Log::Any::Proxy::".
If instead you want to pass the full name of a proxy class, prefix it with
a "+". E.g.

    # Log::Any::Proxy::Foo
    my $log = Log::Any->get_logger(proxy_class => 'Foo');

    # MyLog::Proxy
    my $log = Log::Any->get_logger(proxy_class => '+MyLog::Proxy');

=head2 Logging

To log a message, pass a single string to any of the log levels or aliases. e.g.

    $log->error("this is an error");
    $log->warn("this is a warning");
    $log->warning("this is also a warning");

You should B<not> include a newline in your message; that is the responsibility
of the logging mechanism, which may or may not want the newline.

There are also versions of each of these methods with an additional "f" suffix
(C<infof>, C<errorf>, C<debugf>, etc.) that format a list of arguments.  The
specific formatting mechanism and meaning of the arguments is controlled by the
L<Log::Any::Proxy> object.

    $log->errorf("an error occurred: %s", $@);
    $log->debugf("called with %d params: %s", $param_count, \@params);

By default it renders like C<sprintf>, with the following additional features:

=over

=item *

Any complex references (like C<\@params> above) are automatically converted to
single-line strings with C<Data::Dumper>.

=item *

Any undefined values are automatically converted to the string "<undef>".

=back

=head2 Log level detection

To detect whether a log level is on, use "is_" followed by any of the log
levels or aliases. e.g.

    if ($log->is_info()) { ... }
    $log->debug("arguments are: " . Dumper(\@_))
        if $log->is_debug();

This is important for efficiency, as you can avoid the work of putting together
the logging message (in the above case, stringifying C<@_>) if the log level is
not active.

The formatting methods (C<infof>, C<errorf>, etc.) check the log level for you.

Some logging mechanisms don't support detection of log levels. In these cases
the detection methods will always return 1.

In contrast, the default logging mechanism - Null - will return 0 for all
detection methods.

=head2 Setting an alternate default logger

To choose something other than Null as the default, pass it as a parameter when
loading C<Log::Any>

    use Log::Any '$log', default_adapter => 'Stderr';

The name of the default class follows the same rules as used by L<Log::Any::Adapter>.

=head2 Configuring the proxy

Any parameter passed on the import line or via the C<get_logger> method
are passed on the the L<Log::Any::Proxy> constructor.

    use Log::Any '$log', filter => \&myfilter;

=head2 Testing

L<Log::Any::Test> provides a mechanism to test code that uses C<Log::Any>.

=head1 CONSUMING LOGS (FOR APPLICATIONS)

Log::Any provides modules with a L<Log::Any::Proxy> object, which is the log
producer.  To consume its output and direct it where you want (a file, the
screen, syslog, etc.), you use L<Log::Any::Adapter> along with a
destination-specific subclass.

For example, to send output to a file via L<Log::Any::Adapter::File>, your
application could do this:

    use Log::Any::Adapter ('File', '/path/to/file.log');

See the L<Log::Any::Adapter> documentation for more details.

=head1 Q & A

=over

=item Isn't Log::Any just yet another logging mechanism?

No. C<Log::Any> does not include code that knows how to log to a particular
place (file, screen, etc.) It can only forward logging requests to another
logging mechanism.

=item Why don't you just pick the best logging mechanism, and use and promote it?

Each of the logging mechanisms have their pros and cons, particularly in terms
of how they are configured. For example, log4perl offers a great deal of power
and flexibility but uses a global and potentially heavy configuration, whereas
C<Log::Dispatch> is extremely configuration-light but doesn't handle
categories. There is also the unnamed future logger that may have advantages
over either of these two, and all the custom in-house loggers people have
created and cannot (for whatever reason) stop using.

=item Is it safe for my critical module to depend on Log::Any?

Our intent is to keep C<Log::Any> minimal, and change it only when absolutely
necessary. Most of the "innovation", if any, is expected to occur in
C<Log::Any::Adapter>, which your module should not have to depend on (unless it
wants to direct logs somewhere specific). C<Log::Any> has no non-core dependencies.

=item Why doesn't Log::Any use I<insert modern Perl technique>?

To encourage CPAN module authors to adopt and use C<Log::Any>, we aim to have
as few dependencies and chances of breakage as possible. Thus, no C<Moose> or
other niceties.

=back

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at L<https://github.com/dagolden/Log-Any/issues>.
You will be notified automatically of any progress on your issue.

=head2 Source Code

This is open source software.  The code repository is available for
public review and contribution under the terms of the license.

L<https://github.com/dagolden/Log-Any>

  git clone https://github.com/dagolden/Log-Any.git

=head1 AUTHORS

=over 4

=item *

Jonathan Swartz <swartz@pobox.com>

=item *

David Golden <dagolden@cpan.org>

=back

=head1 CONTRIBUTORS

=for stopwords cm-perl Doug Bell Lucas Kanashiro Maxim Vuets Stephen Thirlwall

=over 4

=item *

cm-perl <cm-perl@users.noreply.github.com>

=item *

Doug Bell <madcityzen@gmail.com>

=item *

Lucas Kanashiro <kanashiro.duarte@gmail.com>

=item *

Maxim Vuets <maxim.vuets@booking.com>

=item *

Stephen Thirlwall <sdt@dr.com>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Jonathan Swartz and David Golden.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
