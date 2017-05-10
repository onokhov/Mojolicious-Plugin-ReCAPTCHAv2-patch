package Mojolicious::Plugin::ReCAPTCHAv2;

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream;
use Hash::Merge::Simple 'clone_merge';

# our $VERSION = ???;

sub register {
    my( $plugin, $app, $conf ) =  @_;

    $plugin->{config} = clone_merge { response_name => 'captcha', timeout => 5 },
                                    $conf // {},
                                    $app->config( 'reCAPTCHAv2' ) // {};

    $plugin->{config}{on_success}
        //= sub { delete $_[0]->req->{params}{ $plugin->{config}{response_name} } };
    
    $plugin->{config}{on_error}
        //= sub { $_[0]->render( status => 400, json => { error => $_[1] } ) };

    $plugin->{config}{$_} //= 1 for 'async', 'defer';    

    die __PACKAGE__ . ": captcha condition is not defined."
        unless $plugin->{config}{condition};
    
    unless ( 'CODE' eq ref $plugin->{config}{condition} ) {
        my $routes = $plugin->{config}{condition};
        $routes = [$routes] unless ref $routes;
        
        die __PACKAGE__ . ": captcha condition is incorrect."
            unless 'ARRAY' eq ref $routes;
        
        $plugin->{config}{routes}{$_}++ for @$routes;
        
        $plugin->{config}{condition}
            = sub { exists $plugin->{config}{routes}{ $_[0]->current_route } };
    }
    
    $plugin->{config}{ua}
        = Mojo::UserAgent->new->request_timeout( $plugin->{config}{timeout} );

    die __PACKAGE__ . ": 'sitekey' is missing" unless $plugin->{config}{sitekey};
    
    die __PACKAGE__ . ": 'secret' is missing"  unless $plugin->{config}{secret};
    
    die __PACKAGE__ . ": $_ must be code ref."
        for grep 'CODE' ne ref($plugin->{config}{$_}), qw(on_success on_error);

    $app->hook( around_action => sub { $plugin->check_captcha(@_) } );

    $app->helper( recaptcha_script => sub { $plugin->recaptcha_script(@_) } );

    $app->helper( recaptcha_div => sub { $plugin->recaptcha_div(@_) } );

}

sub check_captcha {
    my $self = shift;
    my( $next, $c, $action, $last ) =  @_;
    return $next->() unless $last;
    return $next->() unless $self->{config}{condition}->($c);

    my $response = $c->param($self->{config}{response_name})
        or return $self->{config}{on_error}->($c, "$self->{config}{response_name} required");

    return $c->delay(
            sub {
                my $delay = shift;
                $self->{config}{ua}
                    ->post('https://www.google.com/recaptcha/api/siteverify'
                           => form => { secret   => $self->{config}{secret},
                                        response => $response,
                                        remoteip => $c->req->headers->header('X-Real-IP') // $c->tx->remote_address,
                                      } => $delay->begin );
            },
            sub {
                my ($delay, $tx) = @_;
                
                if ( my $err = $tx->error ) { # network or google fault
                    $c->app->log->error(sprintf "Can't verify captcha: %s %s", $err->{code} // '', $err->{message} // '');
                    $self->{config}{on_error}->($c, "$self->{config}{response_name} validation error");
                }
                elsif ( $tx->res->json('/success') ) { # vaidated ok
                    $self->{config}{on_success}->($c, , $tx->res->json);
                    $next->();
                }
                else { # failed validation
                    my $message = "$self->{config}{response_name} invalid";                    
                    my $err_codes = $tx->res->json('/error-codes');
                    if ( $err_codes and grep !/input-response/, @$err_codes ) {
                        $c->app->log->error("Can't verify captcha. Check your config: " . join ', ', @$err_codes);
                        $message = "$self->{config}{response_name} validation error";                        
                    }
                    $self->{config}{on_error}->($c, $message, $tx->res->json);
                }
            }
           );
};

sub recaptcha_script {
    my $self = shift;
    my ($c, %args) = @_;

    my $url = Mojo::URL->new('https://www.google.com/recaptcha/api.js');
    
    $url->query( { @$_ } )
        for grep $_->[1],
            map [ $_ => $args{$_} // $self->{config}{$_} ],
            qw(hl onload render);

    my @parts = ( 'script', qq(src="$url") );
    
    push @parts, grep $args{$_} // $self->{config}{$_}, 'async', 'defer';

    return Mojo::ByteStream->new('<' . join( ' ', @parts ) . '></script>');
}

sub recaptcha_div {
    my $self = shift;
    my ($c, %args) = @_;

    my @parts = ( 'div', 'class="g-recaptcha"' );
    
    push @parts,
         map qq(data-$_->[0]="$_->[1]"),
         grep $_->[1],
         map [ $_ => $args{$_} // $self->{config}{$_} ],
         qw(sitekey theme type size tabindex callback expired-callback);

    return Mojo::ByteStream->new('<' . join( ' ', @parts ) . '></div>');
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::ReCAPTCHAv2 - reCAPTCHA v2 plugin for Mojolicious

=head1 SYNOPSIS

  # Mojolicious::Lite
  plugin ReCAPTCHAv2 => condition => 'feedback',  # route name
                        sitekey   => 'SITEKEY',
                        secret    => 'SECRET';

  post '/feedback' => sub { ... } => 'feedback';


  # Mojolicious

  sub startup {
     my $app = shift;
     ...
     $app->plugin( 'ReCAPTCHAv2' => sitekey   => 'SITEKEY',
                                    secret    => 'SECRET',
                                    condition => ['login','feedback'],
     );
     ...
  };


  # Mojolicious with Config plugin

  # Inside the 'app.conf'
  reCAPTCHAv2 => {
    sitekey   => 'SITEKEY',
    secret    => 'SECRET',
    condition => ['login','feedback'],
    theme     => 'dark',
  },

  # Inside the 'app'
  sub startup {
     my $app = shift;
     ...
     $app->plugin( 'Config' );
     $app->plugin( 'ReCAPTCHAv2' );
     ...
  };


=head1 DESCRIPTION

L<Mojolicious::Plugin::ReCAPTCHAv2> injects non-blocking transparent
captcha protection for any set of routes.

This plugin does all dirty work for you. You do not need to change your controller
code to check if capcha validation succeed. And you can define complicated conditions
which requires captcha for user input. e.g. request frequency threshold, etc.

If your application uses L<Mojolicious::Plugin::Config> you can put configuration
options into application config file and the plugin takes them from the file.


=head1 OPTIONS

Options can be set as parameters on plugin registration or in C<reCAPTCHAv2>
section of app config. Helper specific options can be passed as parameters to helper.
Options from app config have higher precedence than registration parameters and lower
precedence than hepler parameters.

=head2 PLUGIN OPTIONS

=over

=item sitekey

Site key issued by Google for your site upon registration for reCAPTCHA v2.
Required.

=item secret

Secret key issued by Google for your site upon registration for reCAPTCHA v2.
Required.

=item condition

Required. This option defines what routes must be protected with reCAPTCHA v2.
It can be a route name

   condition => 'feedback',

or route names arrayref

   condition => [ 'feedback', 'registration' ],

or a subroutine coderef

   condition => sub {
       my ($c) = @_;
       return unless $c->current_route eq 'feedback';
       my $ip = $c->req->headers->header('X-Real-IP') // $c->tx->remote_address;
       return 1 if redis->get("feedback:$ip");
       redis->setex("feedback:$ip", 300, "need captcha");
       return;
   }

Condition subroutine takes Mojolicious::Controller object as argument and
must return true or false. True means that current route requres captcha
protection. False means no protection required.

=item response_name

Name of parameter with captcha response. Defines what parameter to pass
Google for validation. Default is C<captcha>.

=item timeout

Timeout for validation process in seconds. Default is C<5>.

=item on_error

A code ref to on_error callback. This subroutine renders response in case of
validation failed. It takes Mojolicious::Controller object, error message
and hashref of validation response as arguments. Default value is like this:

  on_error => sub {
     my ($c, $error_message, $res) = @_;
     $c->render( status => 400, json => { error => $error_message } );
  }

The message is C<"captcha invalid"> if captcha response is invalid and
C<"captcha validation error"> if validation is failed for other reasons.
If L</response_name> option is set it is used instead of 'capthca'.

=item on_success

A code ref to on_success callback. This subroutine is called after successful
captcha validation but before passing control to protected route in case of
successfull captcha validation. It takes Mojolicious::Controller object and
hashref of decoded json validaton response as arguments. Default callback
just removes 'capthca' parameter from request parameters. It looks like this:

  on_success => sub {
    my ($c, $r) = @_;
    delete $c->req->{params}{captcha};
  }

=back

=head2 HELPER OPTIONS

Theese options are used for reCAPTCHA v2 widget customization on frontend.
Helper options can be passed as arguments to helper functions, can be defined
in in app config or can be defined as parameters on plugin registration call.
Arguments of helper functions have highest precedence. Arguments of plugin
registration call have lowes precedence. 
See L<https://developers.google.com/recaptcha/docs/display> for full
options description.

=head3 OPTIONS FOR C<recaptcha_script>

=over

=item C<onload>

=item C<render>

=item C<hl>

=item C<async>

True or False. Default C<1>

=item C<defer>

True or False. Default C<1>

=back

=head3 OPTIONS FOR C<recaptcha_div>

=over

=item C<theme>

=item C<type>

=item C<size>

=item C<tabindex>

=item C<callback>

=item C<expired-callback>

=back

=head1 METHODS

L<Mojolicious::Plugin::DefaultHelpers> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register helpers in L<Mojolicious> application.

=head1 HELPERS

L<Mojolicious::Plugin::ReCAPTCHAv2> implements the following helpers.

=head2 recaptcha_script

Includes Google reCAPTCHA v2 javascript library. Uses L</OPTIONS FOR recaptcha_script>

  %= recaptcha_script

would give you

  <script src="https://www.google.com/recaptcha/api.js" async defer></script>

=head2 recaptcha_div

Generates reCAPTCHAv2 div element. Uses L</OPTIONS FOR recaptcha_div>

  <%= recaptcha_div theme => 'dark' %>

gives

  <div class="g-recaptcha" data-sitekey="SITEKEY" data-theme="dark"></div>

=head1 SEE ALSO

L<https://developers.google.com/recaptcha/intro>, L<Mojolicious>, L<Mojolicious::Plugin>.


=cut
