# CircleCI monorepo

[![CircleCI](https://circleci.com/gh/labs42io/circleci-monorepo/tree/master.svg?style=svg)](https://circleci.com/gh/labs42io/circleci-monorepo/tree/master)

> **UPDATE**  
> There is now support for detecting changed files and running multistage workflows natively in CircleCI. See these links:
> https://medium.com/nerd-for-tech/mastering-monorepos-with-circlecis-new-dynamic-config-2e187fe7934c
> https://circleci.com/blog/introducing-dynamic-config-via-setup-workflows/
---

> **UPDATE**  
> There is a new *experimental* script in branch [`v2`](https://github.com/labs42io/circleci-monorepo/tree/v2) that has the following improvements: 
> - Improved calculation of base commit for new branches that takes into account also the history of past CI builds. Current script doesn't identify correctly the parent when creating new branches from merge commits.
> - Improved diff calculation using the two-dot *git diff* command.
> - Improved calculation of CI workflow status that considers success when all jobs succeeds. Current script considers a workflow successful when at least one job succeeds. 
> - Possibility to customize the list of packages with advanced path specifications, that allows to list multiple paths for each package as well as exclude certain paths. 
> - Possibility to provide additional custom pipeline parameters.
> - Possibility to customize the number of API pages with jobs to get from CircleCI. Existing script takes only the first page with 100 jobs.
>   
> The new script is planned to be published as CircleCI orb to allow for easier integration.


Monorepo brings simplicity to the development process by having all code in one place, but raises the complexity of automated builds and deploy.

For a relatively small monorepo it can be acceptable to have builds run for each service on every change.
However, if you have a monorepo with a dozen of services/components, even the smallest change can introduce
big delays in the CI process making it less efficient.

This repository is an example of configuring CircleCI for a monorepo that has four services.
The CircleCI configuration file has workflows defined per each service, that are triggered on every push only when the corresponding service has code changes.

The sample services/components are `api`, `app`, `auth` and `gateway` all located in the subdirectory `/packages`.
For each service a CircleCI workflow with the same name is defined in `.circleci/config.yml` file.


## Important Disclaimer
This repository relies on CircleCI API v2 changes which are currently in [Preview release](https://github.com/CircleCI-Public/api-preview-docs/tree/master/docs).
> Use of the v2 API as long as this notice is in the master branch (current as of June 2019) is done at your own risk and is governed by CircleCI’s Terms of Service.

Additionally, it requires use of v2.1 configuration files as well as having [Pipelines](https://circleci.com/docs/2.0/build-processing/) enabled.

## How it works
Whenever a change is pushed to GIT, by default the `ci` workflow is triggered in CircleCI.
The `ci` workflow consist of a single job `trigger-workflows`, which performs a `checkout` and executes the `circle_trigger.sh` bash script from the `.circleci` folder. The `circle_trigger.sh` bash script is then responsible for detecting which services contain code changes and trigger their corresponding workflow via CircleCI API 2.0.

By convention, each service is located in a separate directory in `packages`.
For each service there should be a separate workflow defined in the `workflows` section in `.circleci/config.yml` configuration file. The workflow is matched by the service's name, which is the same as the directory name from `packages`.

Each workflow is conditioned using a `when` clause, that depends on a pipeline parameter. The name of the parameter is the same as the name of the service.

### Change detection
Each workflow that corresponds to a service is triggered only when there are code changes in the corresponding service directory.
Below is a more detailed explanation of how it detects changes:

- The first step consists of finding the commit SHA of the changes for which the most recently CircleCI pipeline was triggered
  - Firstly it attempts to get the latest completed CircleCI workflow for current branch (together with the commit SHA)
  - If there are no builds for current branch (which is usually the case with feature branches),
    it looks for nearest parent branch and gets its commit SHA (using this [solution](https://gist.github.com/joechrysler/6073741))
  - If there are no builds for parent branch then it uses `master`
- Once it has the commit SHA of latest CircleCI workflow, it uses `git log` to list all changes between the two commits and flag those services for which changes are found in their directories.

## Before you start
To be able to trigger workflows via API, you need a CircleCI [personal API token](https://circleci.com/docs/2.0/managing-api-tokens/#creating-a-personal-api-token).
The `circle_trigger.sh` script expects to find the token in `CIRCLE_TOKEN` environment variable.
To prevent having the tokens published to git, you can use [project environment variables](https://circleci.com/docs/2.0/env-vars/#setting-an-environment-variable-in-a-project).

## How to configure new services/components
Once you add a new service/component to your monorepo you have to do the following steps:

- Add a directory in `packages/` that will be the root of your service/component. The name of the directory will be used as the name of the service/component.

- In `.circleci/config.yml` configuration file in `parameters` section add a corresponding parameter:

```yaml
parameters:
  my_awesome_service: # this should be the name of your service
    type: boolean
    default: false
```

- In `.circleci/config.yml` configuration file in `jobs` section define all the jobs that are need by current service/component.
To set the job's working directory to the directory of the service, you can use job parameter:

```yaml
build:
  parameters:
    package_name:
      type: string

  working_directory: ~/project/packages/<< parameters.package_name >>
  ...
  steps:
    - checkout:
        path: ~/project
```

- In `.circleci/config.yml` configuration file in `workflows` section add a corresponding workflow:

```yaml
workflows:
  when: << pipeline.parameters.my_awesome_service >> # the name of the parameter is the same as service name
    jobs:
      # add here the jobs used by this workflow
```

You have no restrictions on which jobs can be used by each workflow. It can be a service specific job, or a job reused by several workflows (services).
In case you have dependencies between jobs within a workflow, you can have a custom name for the job and then use that name as a requirement:

```yaml
service:
  ...
  jobs:
    - build:
        name: service-build # give a name for the `build` job used in current workflow
        package_name: service # name of the service passed as parameter; used to set the working directory
        ...
    - deploy:
        ...
        requires:
          - service-build # list as a dependency the `build` job from this workflow
```

## Further notes

### Customizing the token
In CircleCI dashboard when viewing a job details you can see who triggered it. In this case it will be the team member whose API token is configured in `CIRCLE_TOKEN` environment variable (described above).

It would be nicer to show there the name of the team member who made the code changes and triggered the workflow.
This allows to see then who triggered a specific job, and have a better integration with CircleCI notifications.


Unfortunately CircleCI currently doesn't support user specific environment variables. One way to workaround it is to define in the CircleCI project
a variable for each team member by following a convention, and then use the built-in `$CIRCLE_USERNAME` to get the name of the variable:

```bash
TOKEN_NAME=CIRCLE_TOKEN_${CIRCLE_USERNAME} # this however will fail if username contain chars like `-`, '.' etc.
CIRCLE_TOKEN=${!TOKEN_NAME}
```

### Dependencies
Dependencies can be handled using [circleci's advanced logic](https://discuss.circleci.com/t/advanced-logic-in-config/36011) with the `or` operator.

Example: if package `api` depends on `common`, you should add `common` as a pipeline parameter and use it to define the `when` parameter for api's workflow

```yaml
workflows:
  version: 2

  # The main workflow responsible for triggering all other workflows
  # in which changes are detected.
  ci:
    when: << pipeline.parameters.trigger >>
    jobs:
      - trigger-workflows


  # Workflows defined for each package.

  api:
    when: 
      or: 
        - << pipeline.parameters.api >>
        - << pipeline.parameters.common >>
    jobs:
      - build:
          name: api-build
          package_name: api
      - deploy:
          name: api-deploy
          package_name: api
          requires:
            - api-build
```

Now, changes in package `common` will also trigger build for `api`
