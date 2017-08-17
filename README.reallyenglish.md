Table of Contents
=================

  * [Building and testing box images](#building-and-testing-box-images)
    * [box.reallyenglish.yml](#boxreallyenglishyml)
    * [building a box](#building-a-box)
    * [Testing all the boxes listed in box.reallyenglish.yml](#testing-all-the-boxes-listed-in-boxreallyenglishyml)
    * [Cleaning after build](#cleaning-after-build)

# Building and testing box images

The `Rakefile` has a name space, `reallyenglish` in which tasks that
build boxes and run `serverspec` because the original `Rakefile` lacks
comprehensive tests. The name space is intended to include tasks
specific to the organization. When building a box the tasks in the name
space should be used.

## Branches

Our forked repository has two main branches; `master` that follows the
upstream's `master` branch, and `reallyenglish-master` that is the master
branch for production and development. `reallyenglish-master` is the default
branch, into which all the fixes, modifications, and enhancement specific to
the organization are merged. When you merge a development branch, be sure to
merge it into `reallyenglish-master` unless you are updating `master` branch.

## `box.reallyenglish.yml`

The file contains a list of box names that the organization is using.

## building a box

`do_test` task takes an argument, the name of the box to build.

```sh
bundle exec rake 'reallyenglish:do_test[$BOXNAME]'
```

The task does the followings:

* builds a box
* imports the box built into your local box list as `test-$BOXNAME`
* `vagrant up` the box
* runs `serverspec` under `reallyenglish_spec` directory
* destroys the VM

Each step can be invoked by corresponding sub-tasks.

## Testing all the boxes listed in `box.reallyenglish.yml`

A target `test` performs `do_test` task in a loop and tests all the box
listed in `box.reallyenglish.yml`.

## Cleaning after build

`clean` target runs `vagrant destroy -f` and removes box files.
