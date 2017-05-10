use strict;
use warnings;

use Mojolicious::Lite;
use Test::Mojo;
use Test::More;
 
#use_ok('Mojolicious::Plugin::ReCAPTCHAv2');

plugin ReCAPTCHAv2 => sitekey => 'SITEKEY', secret => 'SECRET', condition => 'protectme', defer => 0, theme => 'dark';
 
get '/' => sub {
  my $c = shift;
  $c->render(template => 'index');
};
 
any '/protectme' => sub {
  my $c = shift;
  $c->render(text => 'ok');
} => 'protectme';

my $t = Test::Mojo->new;
$t->get_ok('/')->status_is(200)
    ->content_like(qr(\Q<script src="https://www.google.com/recaptcha/api.js?hl=en" async></script>))
    ->content_like(qr(\Q<div class="g-recaptcha" data-sitekey="SITEKEY" data-theme="dark"></div>))
    ;

$t->get_ok('/protectme')->status_is(400)->json_is('/error', 'captcha required');

$t->post_ok('/protectme' => form => { captcha => 'captcha' })->status_is(400)->json_is('/error', 'captcha validation error');

diag $t->tx->res->body;

done_testing;

__DATA__

@@ index.html.ep

%= recaptcha_script hl => 'en'
%= recaptcha_div

    

