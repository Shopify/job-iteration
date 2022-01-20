#!/usr/bin/env bash

set -ex

mysql -h mysql -uroot -e "CREATE DATABASE job_iteration_test"
