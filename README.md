# NAME

Mojolicious::Plugin::ReCAPTCHAv2 - reCAPTCHA v2 plugin for Mojolicious (replacement patch)

# SYNOPSIS

```
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
```


# DESCRIPTION

[Mojolicious::Plugin::ReCAPTCHAv2] injects non-blocking transparent
captcha protection for any set of routes.

This plugin does all dirty work for you. You do not need to change your controller
code to check if capcha validation succeed. And you can define complicated conditions
which requires captcha for user input. e.g. request frequency threshold, etc.

If your application uses [Mojolicious::Plugin::Config] you can put configuration
options into application config file and the plugin takes them from the file.


# OPTIONS

Options can be set as parameters on plugin registration or in `reCAPTCHAv2`
section of app config. Helper specific options can be passed as parameters to helper.
Options from app config have higher precedence than registration parameters and lower
precedence than hepler parameters.

## PLUGIN OPTIONS

- `sitekey`

Site key issued by Google for your site upon registration for reCAPTCHA v2.
Required.

- `secret`

Secret key issued by Google for your site upon registration for reCAPTCHA v2.
Required.

- `condition`

Required. This option defines what routes must be protected with reCAPTCHA v2.
It can be a route name

```
   condition => 'feedback',
```

or route names arrayref

```
   condition => [ 'feedback', 'registration' ],
```

or a subroutine coderef

```
   condition => sub {
       my ($c) = @_;
       return unless $c->current_route eq 'feedback';
       my $ip = $c->req->headers->header('X-Real-IP') // $c->tx->remote_address;
       return 1 if redis->get("feedback:$ip");
       redis->setex("feedback:$ip", 300, "need captcha");
       return;
   }
```

Condition subroutine takes Mojolicious::Controller object as argument and
must return true or false. True means that current route requres captcha
protection. False means no protection required.

- `disabled`

```
  reCAPTCHAv2 => {
    ...
    disabled => 1,
    ...
  },
```
  
Set it true if you want to completely skip captcha validation. This can be useful
for autotests. Environment variable `CAPTCHA_DISABLED` has the same effect.

- `response_name`

Name of parameter with captcha response. Defines what parameter to pass
Google for validation. Default is `captcha`.

- `header`

```
  header => 'X-Captcha',
```
  
If `header` is set, than captcha response value expected in this header
instead of request parameter

- `timeout`

Timeout for validation process in seconds. Default is `5`.

- `on_error`

A code ref to on_error callback. This subroutine renders response in case of
validation failed. It takes Mojolicious::Controller object, error message
and hashref of validation response as arguments. Default value is like this:

```
  on_error => sub {
     my ($c, $error_message, $res) = @_;
     $c->render( status => 400, json => { error => $error_message } );
  }
```

The message is `"captcha invalid"` if captcha response is invalid and
`"captcha validation error"` if validation is failed for other reasons.
If [response_name] option is set it is used instead of 'capthca'.

- `on_success`

A code ref to on_success callback. This subroutine is called after successful
captcha validation but before passing control to protected route in case of
successfull captcha validation. It takes Mojolicious::Controller object and
hashref of decoded json validaton response as arguments. Default callback
just removes 'capthca' parameter from request parameters. It looks like this:

```
  on_success => sub {
    my ($c, $r) = @_;
    delete $c->req->{params}{captcha};
  }
```


## HELPER OPTIONS

Theese options are used for reCAPTCHA v2 widget customization on frontend.
Helper options can be passed as arguments to helper functions, can be defined
in in app config or can be defined as parameters on plugin registration call.
Arguments of helper functions have highest precedence. Arguments of plugin
registration call have lowes precedence. 
See [https://developers.google.com/recaptcha/docs/display] for full
options description.

### OPTIONS FOR `recaptcha_script`


- `onload`

- `render`

- `hl`

- `async`

True or False. Default `1`

- `defer`

True or False. Default `1`


### OPTIONS FOR `recaptcha_div`


- `theme`

- `type`

- `size`

- `tabindex`

- `callback`

- `expired-callback`

# METHODS

[Mojolicious::Plugin::DefaultHelpers] inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

## register

```
  $plugin->register(Mojolicious->new);
```

Register helpers in [Mojolicious] application.

# HELPERS

[Mojolicious::Plugin::ReCAPTCHAv2] implements the following helpers.

## recaptcha_script

Includes Google reCAPTCHA v2 javascript library. Uses [/OPTIONS FOR recaptcha_script]

```
  %= recaptcha_script
```

would give you

```
  <script src="https://www.google.com/recaptcha/api.js" async defer></script>
```

## recaptcha_div

Generates reCAPTCHAv2 div element. Uses [/OPTIONS FOR recaptcha_div]

```
  <%= recaptcha_div theme => 'dark' %>
```

gives

```
  <div class="g-recaptcha" data-sitekey="SITEKEY" data-theme="dark"></div>
```

# SEE ALSO

[https://developers.google.com/recaptcha/intro], [Mojolicious], [Mojolicious::Plugin].


