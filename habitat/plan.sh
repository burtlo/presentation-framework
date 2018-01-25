pkg_name=presentation-framework
pkg_origin=franklinwebber
pkg_version="0.1.0"
pkg_scaffolding="core/scaffolding-ruby"

declare -A scaffolding_env

# Add additional variables which use runtime config values
scaffolding_env[LC_ALL]="en_US.UTF-8"

# Below is the default behavior for this callback. Anything you put in this
# callback will override this behavior. If you want to use default behavior
# delete this callback from your plan.
# @see https://www.habitat.sh/docs/reference/plan-syntax/#callbacks
# @see https://github.com/habitat-sh/habitat/blob/master/components/plan-build/bin/hab-plan-build.sh
do_install() {
    build_line "Installing the presentation to the data dir"
    # mkdir -p $pkg_prefix/app/source/presentations
    # cp presentation.html.rmd.erb $pkg_prefix/app/source/presentations/presentation.html.rmd.erb
    cp presentation.html.rmd.erb $pkg_prefix
    build_line "Doing the default install"
    do_default_install
}
