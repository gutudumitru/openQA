#!/usr/bin/perl -w

BEGIN { unshift @INC, 'lib', 'lib/OpenQA/modules'; }

use strict;
use Data::Dump qw/pp dd/;
use Scheduler;
use openqa;

use Test::More tests => 33;

sub nots
{
  my $h = shift;
  my @ts = @_;
  unshift @ts, 't_updated', 't_created';
  for (@ts) {
    delete $h->{$_};
  }
  return $h;
}

my $current_jobs = list_jobs();
is_deeply($current_jobs , [], "assert database has no jobs to start with")
    or BAIL_OUT("database not properly initialized");

# Testing worker_register and worker_get
# New worker
my $id = worker_register("host", "1", "backend");
ok($id == 1, "New worker registered");
my $worker = worker_get($id);
ok($worker->{id} == $id
   && $worker->{host} eq "host"
   && $worker->{instance} eq "1"
   && $worker->{backend} eq "backend", "New worker_get");

# Update worker
sleep(1);
my $id2 = worker_register("host", "1", "backend");
ok($id == $id2, "Known worker_register");
my $worker2 = worker_get($id2);
ok($worker2->{id} == $id2
   && $worker2->{host} eq "host"
   && $worker2->{instance} eq "1"
   && $worker2->{backend} eq "backend"
   && $worker2->{t_updated} ne $worker->{t_updated}, "Known worker_get");

# Testing list_workers
my $workers_ref = list_workers();
ok(scalar @$workers_ref == 2
   && pp($workers_ref->[1]) eq pp($worker2) , "list_workers");


# Testing job_create and job_get
my %settings = (
    DISTRI => 'Unicorn',
    FLAVOR => 'pink',
    VERSION => '42',
    BUILD => '666',
    TEST => 'rainbow',
    ISO => 'whatever.iso',
    DESKTOP => 'DESKTOP',
    KVM => 'KVM',
    ISO_MAXSIZE => 1,
    );

my $job = {
    t_finished => undef,
    id => 1,
    name => 'Unicorn-42-Build666-rainbow',
    priority => 40,
    result => 'none',
    settings => {
        DESKTOP => "DESKTOP",
        DISTRI => 'Unicorn',
        FLAVOR => 'pink',
        VERSION => '42',
        BUILD => '666',
        TEST => 'rainbow',
        ISO => 'whatever.iso',
        ISO_MAXSIZE => 1,
        KVM => "KVM",
    },
    t_started => undef,
    state => "scheduled",
    worker_id => 0,
    };

my $iso = sprintf("%s/%s/factory/iso/%s", $openqa::basedir, $openqa::prj, $settings{ISO});
open my $fh, ">", $iso;
my $job_id = Scheduler::job_create(%settings);
is($job_id, 1, "job_create");
my %settings2 = %settings;
$settings2{NAME} = "OTHER NAME";
my $job2_id = Scheduler::job_create(%settings2);
unlink $iso;

Scheduler::job_set_prio(jobid => $job_id, prio => 40);
my $new_job = Scheduler::job_get($job_id);
is_deeply($new_job, $job, "job_get");

# Testing list_jobs
my $jobs = [
    {
        t_finished => undef,
        id => 1,
        name => 'Unicorn-42-Build666-rainbow',
        priority => 40,
        result => 'none',
        t_started => undef,
        state => "scheduled",
        worker_id => 0,
    },
    {
        t_finished => undef,
        id => 2,
        name => "OTHER NAME",
        priority => 50,
        result => 'none',
        t_started => undef,
        state => "scheduled",
        worker_id => 0,
    },
];

$current_jobs = list_jobs();
is_deeply($current_jobs , $jobs, "All list_jobs");

my %state = (state => "scheduled");
$current_jobs = list_jobs(%state);
is_deeply($current_jobs, $jobs, "All list_jobs with state scheduled");

%state = (state => "running");
$current_jobs = list_jobs(%state);
is_deeply($current_jobs, [], "All list_jobs with state running");


# Testing job_grab
my %args = (
    workerid => $worker->{id},
    );
my $rjobs_before = Scheduler::list_jobs(state => 'running');
$job = Scheduler::job_grab(%args);
my $rjobs_after = Scheduler::list_jobs(state => 'running');
ok(pp($job->{settings}) eq pp(\%settings) && length $job->{t_started} == 19 && scalar(@{$rjobs_before})+1 == scalar(@{$rjobs_after}), "job_grab");


# # Testing when a worker register for second time and had pending jobs
# $id2 = worker_register("host", "instance", "backend");
# ok($id == $id2, "Pending jobs worker_register");


# Testing job_set_scheduled
$job = Scheduler::job_get($job_id);
ok($job->{state} eq "running", "Job is in running state");   # After job_grab the job is in running state.

my $result = Scheduler::job_set_scheduled($job_id);
$job = Scheduler::job_get($job_id);
ok($result == 1&& $job->{state} eq "scheduled", "job_set_scheduled");

# Testing job_set_done
%args = (
    jobid => $job_id,
    result => 'passed',
    );
$result = Scheduler::job_set_done(%args);
ok($result == 1, "job_set_done");
$job = Scheduler::job_get($job_id);
is($job->{state}, "done", "job_set_done changed state");
is($job->{result}, "passed", "job_set_done changed result");


# Testing job_set_cancel
$result = Scheduler::job_set_cancel($job_id);
$job = Scheduler::job_get($job_id);
ok($result == 1 && $job->{state} eq "cancelled", "job_set_cancel");


# Testing job_set_waiting
$result = Scheduler::job_set_waiting($job_id);
$job = Scheduler::job_get($job_id);
ok($result == 1 && $job->{state} eq "waiting", "job_set_waiting");


# Testing job_set_running
$result = Scheduler::job_set_running($job_id);
$job = Scheduler::job_get($job_id);
ok($result == 1 && $job->{state} eq "running", "job_set_running");
$result = Scheduler::job_set_running($job_id);
$job = Scheduler::job_get($job_id);
ok($result == 0 && $job->{state} eq "running", "Retry job_set_running");


# Testing job_set_prio
%args = (
    jobid => $job_id,
    prio => 100,
    );
$result = Scheduler::job_set_prio(%args);
$job = Scheduler::job_get($job_id);
ok($result == 1 && $job->{priority} == 100, "job_set_prio");


# Testing job_update_result
%args = (
    jobid => $job_id,
    result => 'passed',
    );
$result = Scheduler::job_update_result(%args);
ok($result == 1, "job_update_result");
$job = Scheduler::job_get($job_id);
is($job->{result}, $args{result}, "job_get after update");


# Testing job_restart
# TBD

# Testing job_cancel
# TBD

# Testing job_fill_settings
# TBD


# Testing job_delete
$result = Scheduler::job_delete($job_id);
my $no_job_id = Scheduler::job_get($job_id);
ok($result == 1 && !defined $no_job_id, "job_delete");
my $fake_job = { id => $job_id };
Scheduler::_job_fill_settings($fake_job);
ok(pp($fake_job->{settings}) eq "{}", "Cascade delete");

$result = Scheduler::job_delete($job2_id);
$no_job_id = Scheduler::job_get($job_id);
ok($result == 1 && !defined $no_job_id, "job_delete");

$current_jobs = list_jobs();
is_deeply($current_jobs , [], "no jobs listed");

# Testing command_enqueue and list_commands
%args = (
    workerid => $id,
    command => "command",
    );
my %command = (
    id => 1,
    worker_id => 1,
    command => "command",
    );
my $command_id = Scheduler::command_enqueue(%args);
my $commands = Scheduler::list_commands();
ok($command_id == 1 && @$commands == 1, "one command listed");

is_deeply(nots($commands->[0], 't_processed'), \%command,  "command entered correctly");


# Testing command_get
$commands = Scheduler::command_get($command_id);
ok(scalar @$commands == 1 && pp($commands) eq '[[1, "command"]]',  "command_get");


# Testing command_dequeue
# TBD

TODO: {
    local $TODO = "get job by iso name still to be implemented";
# Testing iso_cancel_old_builds
$result = Scheduler::iso_cancel_old_builds('ISO');
ok($result == 1, "Empty iso_old_builds");
open $fh, ">", $iso;
$job_id = Scheduler::job_create(%settings);
unlink $iso;
$result = Scheduler::iso_cancel_old_builds('ISO');
$new_job = Scheduler::job_get($job_id);
ok($result == 1 && $new_job->{state} eq "cancelled" && $new_job->{worker_id} == 0, "Match iso_old_builds");
}