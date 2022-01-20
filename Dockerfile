FROM ruby:2.7.5

RUN apt-get update && apt-get install -y default-mysql-client

RUN mkdir -p work
WORKDIR /work

RUN gem install bundler -N
RUN mkdir -p lib/job-iteration

ADD Gemfile .
ADD job-iteration.gemspec .
ADD ./lib/job-iteration/version.rb lib/job-iteration/

RUN bundle

ADD . .

