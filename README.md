# CircleCI monorepo

[![CircleCI](https://circleci.com/gh/labs42io/circleci-monorepo/tree/master.svg?style=svg)](https://circleci.com/gh/labs42io/circleci-monorepo/tree/master)

This repository is an example of configuring CircleCI for a monorepo that has four services.
The CircleCI configuration file has workflows defined per each service, that are triggered on every push only when the corresponding service has code changes.

The sample services/packages are `api`, `app`, `auth` and `gateway` all located in the subdirectory `packages/`.
For each service a CircleCI workflow is defined in `.circleci/config.yml` file.


## Important Disclaimer
This repository relies on CircleCI API v2 changes which are currently in [Preview release](https://github.com/CircleCI-Public/api-preview-docs/tree/master/docs).
> Use of the v2 API as long as this notice is in the master branch (current as of June 2019) is done at your own risk and is governed by CircleCI’s Terms of Service.

Additionally, it requires use of v2.1 configuration files as well as having [Pipelines](https://circleci.com/docs/2.0/build-processing/) enabled.

## How it works
Whenever a change is pushed to GIT, a default `ci` workflow is triggered in CircleCI.
The `ci` workflow consists of a single job `trigger-workflows`, which performs a `checkout` and executes the `.circleci/monorepo.sh` bash script.
The `monorepo.sh` script is then responsible for detecting which packages were changed and trigger their corresponding workflows via CircleCI API v2.0.

### Diff changes

The workflows are triggered based on calculated changes. The changes for each package are calculated according to following algorithm:

- **Pushes for which the package has successful workflows in current branch:** A two-dot diff compares the head and the SHA of the latest successful workflow.
- **Pushes to new branches:** A two-dot diff compares the head and the SHA of the latest commit that:
  - is also part of the history of another branch 
  - is prior to any other commits from the current branch for which a CI was run.

**Examples**

<pre>
A---B---C---D (master branch)  
     \
      E---F (feature branch)
</pre>

Suppose in above example a feature branch has been created from *master* branch. The commit `E` was pushed in feature branch with changes in package `P1`. 
In this case this branch is new and there are no commits for `P1`. The base SHA for diff is considered commit `B` as it is the first commit common to both, feature branch and the master branch. `P1` workflow ONLY is triggered, as there are no diff changes for other packages since commit `B`.  
Now, let's say we push additional commit `F` with changes in package `P1` and `P2`. For `P1` there is commit `E` in current branch that has a passed CI workflow and
therefore it is used as a diff base. For `P2` as in the previous case, the diff base is considered commit `B`.  
 
Now let's consider a more complex example.

<pre>
A---B---C---D (master branch)  
 \   \
  \   E---F---G   (feature branch F1)
   \       \
    H---I---J---K (feature branch F2)
</pre>

In this example we have two feature branches `F1` and `F2`. Let's say feature branch `F2` was first pushed with commit `H`.
Later, feature branch `F1` was merged into `F2` with merge commit `J`. When triggering the pipeline at commit `J`, the workflows for which there are
builds in current branch will consider that commit as a diff base. For workflows that are new, commit `A` is considered as a diff base because
it is common to current branch and `master`, and is prior to commit `H` which is the first pushed commit in current branch.


## Setup

### Personal API token
To be able to trigger workflows via CircleCI API, you need a [personal API token](https://circleci.com/docs/2.0/managing-api-tokens/#creating-a-personal-api-token).
The `monorepo.sh` script expects to find the token in `CIRCLE_USER_TOKEN` environment variable.
To prevent having the tokens published to git, use [project environment variables](https://circleci.com/docs/2.0/env-vars/#setting-an-environment-variable-in-a-project) or [contexts](https://circleci.com/docs/2.0/contexts/).

### Trigger script configurations

#### Defaults

By default, each package is considered to be located in directory `packages/`. The root directory of the packages can be configured, or for more
advanced configurations, there is an option co configure the list of packages and their paths. 

#### Custom paths

To provide custom options, firstly create a `.circleci/monorepo.json` file which should be a valid JSON. 

**Customizing the root directory**  
To configure a custom root directory, provide the `root` option.  
For example, specify that all services are in `src/services` directory (relative to the root of repository):

```json
{
  "root": "src/services"
}
```

Each directory in `src/services` will be treated as a package.

**Customizing list of packages and their paths**  
To have the full control of which packages to list and what paths to use, provide the `packages` option.  
The `packages` object is a key-value pair, where the key is the name of the package (should correspond to pipeline parameter in `.circleci/config.yml` file) and the value is an array of paths (git `pathspec`).  

Example:
```json
{
  "packages": {
    "auth": ["packages/auth/"],
    "api": ["packages/api/**.js"],
    "app": ["packages/app/", ":!packages/app/*.md"]
  }
}
```

Explanation:  
The `auth` package is triggered for any change in `packages/auth/` directory.  
The `api` package is configured to be triggered whenever any `.js` file is changed in `packages/api/` directory, at any level.  
The `app` package is configured to be triggered on any change in `packages/app/` directory, but ignores the changes from `*.md` files.  

The list of paths for each package are provided as is to the `git diff` command when calculating changes between two commits. 
See [pathspec](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-aiddefpathspecapathspec) documentation for a list
of complete options, as well as [this](https://css-tricks.com/git-pathspecs-and-how-to-use-them/) article for more examples.  

Note that `root` and `packages` options are mutually exclusive. Once `packages` is specified, `root` option is ignored and the list of packages should 
be provided explicitly.

#### CircleCI API pages

The `monorepo.sh` script uses CircleCI's [API](https://circleci.com/docs/api/#recent-builds-for-a-single-project) to get the list of jobs in the current branch.
It allows to get only up to *100* jobs in a single page. By default only one page is loaded to get the jobs and from that to calculate which workflows succeeded.  
It is possible to configure more API pages to be loaded from CircleCI:

Example:
```json
{
  "pages": 3
}
```
This will load the latest *300* jobs in the current branch. Note that for each page a CircleCI API call is executed.  
Customizing the number of pages to load might be useful when the repository contains lots of packages and/or workflows are complex and consist of many more jobs.

### CircleCI config.yml changes

#### Configure the trigger workflow 

To configure the trigger workflow follow the steps:

- In `.circleci/config.yml` add a `trigger` pipeline parameter with `true` default value:

```yml
parameters:
  # This parameter is used to trigger the main workflow
  trigger:
    type: boolean
    default: true
```

- Add the trigger job:

```yml
jobs:
  trigger-workflows:
    docker: 
      - image: cimg/base:stable
    steps:
      - checkout
      - run:
          name: Trigger workflows
          command: chmod +x .circleci/monorepo.sh && .circleci/monorepo.sh
```

- Add the trigger workflow

```yml
workflows:
  version: 2

  ci:
    when: << pipeline.parameters.trigger >>
    jobs:
      - trigger-workflows
```


#### Configuring packages
For each configured package in the repository (either by its name in `packages` object from `monorepo.json` file, or the directory name under the configured root)
a corresponding pipeline parameter must be configured in `.circleci/config.yml` file:

```yaml
parameters:
  ...
  app: # corresponds to the name of the package
    type: boolean
    default: false
```

Now, define a package workflow that is conditioned to be triggered only on corresponding changes:  


```yaml
workflows:
  ...
  api:
    when: << pipeline.parameters.api >>
    jobs:
      ...
```

See [.circleci/config.yml](.circleci/config.yml) file for a running example.
