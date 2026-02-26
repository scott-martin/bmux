#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::WebDriver::Element;

# --- Selector strategy detection ---

{
    is(Bmux::WebDriver::Element::selector_strategy('button'), 'css selector', 'simple tag is css');
    is(Bmux::WebDriver::Element::selector_strategy('.class'), 'css selector', 'class is css');
    is(Bmux::WebDriver::Element::selector_strategy('#id'), 'css selector', 'id is css');
    is(Bmux::WebDriver::Element::selector_strategy('div.foo'), 'css selector', 'tag.class is css');
    is(Bmux::WebDriver::Element::selector_strategy('[data-test]'), 'css selector', 'attribute is css');
    is(Bmux::WebDriver::Element::selector_strategy('div > span'), 'css selector', 'child combinator is css');
}

{
    is(Bmux::WebDriver::Element::selector_strategy('/html/body'), 'xpath', 'absolute xpath');
    is(Bmux::WebDriver::Element::selector_strategy('//div'), 'xpath', 'descendant xpath');
    is(Bmux::WebDriver::Element::selector_strategy('//button[@id="submit"]'), 'xpath', 'xpath with predicate');
}

# --- Find element request ---

{
    my $req = Bmux::WebDriver::Element::find_element_request('sess123', 'button.submit');
    
    is($req->{method}, 'POST', 'find element is POST');
    is($req->{path}, '/session/sess123/element', 'find element path');
    is($req->{body}{using}, 'css selector', 'find element using css');
    is($req->{body}{value}, 'button.submit', 'find element value');
}

{
    my $req = Bmux::WebDriver::Element::find_element_request('sess123', '//div[@class="content"]');
    
    is($req->{body}{using}, 'xpath', 'find element using xpath');
    is($req->{body}{value}, '//div[@class="content"]', 'find element xpath value');
}

# --- Find elements request (plural) ---

{
    my $req = Bmux::WebDriver::Element::find_elements_request('sess123', 'li.item');
    
    is($req->{method}, 'POST', 'find elements is POST');
    is($req->{path}, '/session/sess123/elements', 'find elements path (plural)');
    is($req->{body}{using}, 'css selector', 'find elements using css');
    is($req->{body}{value}, 'li.item', 'find elements value');
}

# --- Element ID extraction ---

# WebDriver returns element IDs in a special format
{
    my $response = {
        'element-6066-11e4-a52e-4f735466cecf' => 'actual-element-id-123'
    };
    my $json = encode_json({ value => $response });
    
    my $id = Bmux::WebDriver::Element::extract_element_id($json);
    
    is($id, 'actual-element-id-123', 'extract element id from webdriver format');
}

{
    my $response = {
        'element-6066-11e4-a52e-4f735466cecf' => 'different-id'
    };
    my $json = encode_json({ value => $response });
    
    my $id = Bmux::WebDriver::Element::extract_element_id($json);
    
    is($id, 'different-id', 'extract different element id');
}

# --- Extract multiple element IDs ---

{
    my $response = [
        { 'element-6066-11e4-a52e-4f735466cecf' => 'id-1' },
        { 'element-6066-11e4-a52e-4f735466cecf' => 'id-2' },
        { 'element-6066-11e4-a52e-4f735466cecf' => 'id-3' },
    ];
    my $json = encode_json({ value => $response });
    
    my @ids = Bmux::WebDriver::Element::extract_element_ids($json);
    
    is(scalar @ids, 3, 'extract multiple element ids count');
    is($ids[0], 'id-1', 'first element id');
    is($ids[1], 'id-2', 'second element id');
    is($ids[2], 'id-3', 'third element id');
}

{
    my $json = encode_json({ value => [] });
    
    my @ids = Bmux::WebDriver::Element::extract_element_ids($json);
    
    is(scalar @ids, 0, 'empty array returns no ids');
}

# --- Error when element not found ---

{
    my $json = encode_json({
        value => {
            error => 'no such element',
            message => 'Unable to find element'
        }
    });
    
    eval { Bmux::WebDriver::Element::extract_element_id($json) };
    like($@, qr/no such element/, 'not found throws error');
}

# --- High-level runner with mock client ---

{
    package MockClient;
    sub new { 
        my ($class, $response) = @_;
        bless { calls => [], response => $response }, $class;
    }
    sub session_id { 'mock-session' }
    sub post {
        my ($self, $path, $body) = @_;
        push @{$self->{calls}}, { method => 'POST', path => $path, body => $body };
        return $self->{response};
    }
    sub calls { shift->{calls} }
    
    package main;
    
    my $element_response = { 'element-6066-11e4-a52e-4f735466cecf' => 'found-id' };
    my $client = MockClient->new($element_response);
    
    my $id = Bmux::WebDriver::Element::run_find_element($client, 'button.submit');
    
    is($id, 'found-id', 'run_find_element returns element id');
    is($client->calls->[0]{path}, '/session/mock-session/element', 'run_find_element path');
    is($client->calls->[0]{body}{using}, 'css selector', 'run_find_element using');
    is($client->calls->[0]{body}{value}, 'button.submit', 'run_find_element value');
}

{
    my $elements_response = [
        { 'element-6066-11e4-a52e-4f735466cecf' => 'el-1' },
        { 'element-6066-11e4-a52e-4f735466cecf' => 'el-2' },
    ];
    my $client = MockClient->new($elements_response);
    
    my @ids = Bmux::WebDriver::Element::run_find_elements($client, 'li');
    
    is(scalar @ids, 2, 'run_find_elements returns multiple ids');
    is($client->calls->[0]{path}, '/session/mock-session/elements', 'run_find_elements path');
}

done_testing;
