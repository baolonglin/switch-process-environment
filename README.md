# switch-process-environment

## Motivation
Different projects need different shell environment, but don't want to start several emacs.

Shell environment need to be updated, but don't wnat to call *setenv* several times.

Same project has different compilation mode, need different shell environment, but don't want to start several emacs.

## Known Limitation
* need Emacs version > 25

## Installation
Download switch-process-environment.el, put it into a directory which in *load-path*

## Usage

Add require in your configuration file:
```(require 'switch-process-environment)```

Customize *switch-process-environment-variables*

In your Emacs, execute:

* *switch-process-environment-setup*: load the configured vairables, it can be exeucted multiple time. It removes all runtime environments, if you use *switch-rprocess-environment-save* before, those saved environments will be lost.
* *switch-process-environment-switch*: switch to other environment.
* *switch-process-environment-save*: save current process environment into runtime environments.



