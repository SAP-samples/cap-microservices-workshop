# Exercise 04 - Wire up everything for deployment

👉 Add production features
```sh
cds add mta,hana,xsuaa,approuter

# Since we already have our shared-db project, we do not need the generated db folder
rm -r db
```

This generates a bunch of files, including an `xs-security.json` for the authentication and authorization configuration of the xsuaa instance, an `app/router` folder for serving the ui, and an `mta.yaml` as the deployment descriptor for the [multitarget application deployment](https://help.sap.com/docs/btp/sap-business-technology-platform/mta-deployment-descriptor-examples).

Take a look at the `mta.yaml`.

```yaml
...
build-parameters:
  before-all:
    - builder: custom
      commands:
        - npm ci
        - npx cds build --production
modules:
  - name: solution-srv         # Our backend application - since we have multiple, we will replace this
    type: nodejs
    path: gen/srv
    ...

  - name: solution-db-deployer # Deploying the database artifacts
    type: hdb
    path: gen/db
    ...

  - name: solution             # Serving the UIs and acting as proxy for the backend
    type: approuter.nodejs
    path: app/router
    ...

resources:
  - name: solution-db          # Our persistence
    type: com.sap.xs.hdi-container
    parameters:
      service: hana
      service-plan: hdi-shared
  - name: solution-auth        # For authentication and authorization
    type: org.cloudfoundry.managed-service
    parameters:
      service: xsuaa
      service-plan: application
      path: ./xs-security.json
      config:
        xsappname: solution-${org}-${space}
        tenant-mode: dedicated
```

Here you see multiple modules and resources. The modules are later deployed as Cloud Foundry applications and the resources are created as service instances.


## Separating the apps

The generated code assumes that the current project is meant to be deployed.
It contains a `solution-srv` pointing to the solution srv folder as well as a `solution-db-deployer` that points towards the solution db folder. That's what we need to change.


👉 Remove the build command for the current project and instead add separate build commands for each of our projects
```diff
# mta.yaml
  before-all:
    - builder: custom
      commands:
        - npm ci
-       - npx cds build --production
+       - npx cds build ./shared-db --for hana --production --ws-pack
+       - npx cds build ./incidents --for nodejs --production --ws-pack
+       - npx cds build ./feedback --for nodejs --production --ws-pack
```

Notice the `--ws-pack` option: It packages dependencies during the build that are otherwise symlinks due to the npm workspaces configuration.


👉 Adjust the path reference for the db-deployer
```diff
# mta.yaml
  - name: solution-db-deployer
    type: hdb
-   path: gen/db
+   path: shared-db/gen/db
    ...
```


👉 Instead of a single application, we want to deploy multiple, so we need to replace the `solution-srv` module with ones for incidents and feedback
```diff
- - name: solution-srv
+ - name: incidents-srv
    type: nodejs
-   path: gen/srv
+   path: incidents/gen/srv
    ...
    build-parameters:
-     builder: npm-ci
+     builder: npm
    provides:
-     - name: srv-api
+     - name: incidents-api
    ...
```

👉 Add the additional module for feedback - it is the same as `incidents-srv`, just with `feedback` instead of `incidents`
```diff
# mta.yaml
modules:
  - name: incidents-srv
    ...

+ - name: feedback-srv
+   type: nodejs
+   path: feedback/gen/srv
+   parameters:
+     instances: 1
+     buildpack: nodejs_buildpack
+   build-parameters:
+     builder: npm
+   provides:
+     - name: feedback-api # required by consumers of CAP services (e.g. approuter)
+       properties:
+         srv-url: ${default-url}
+   requires:
+     - name: solution-auth
+     - name: solution-db

  - name: solution-db-deployer
    ...
```

👉 To save costs, reduce the memory footprint of the apps
```diff
# mta.yaml
modules:
  - name: incidents-srv
    ...
    parameters:
+      disk-quota: 256M
+      memory: 256M
    ...
  - name: feedback-srv
    ...
    parameters:
+      disk-quota: 256M
+      memory: 256M
    ...
```



👉 Update the approuter destinations to point towards both application
```diff
# mta.yaml
  - name: solution
    type: approuter.nodejs
    path: app/router
    ...
    requires:
-      - name: srv-api
-        group: destinations
-        properties:
-          name: srv-api # must be used in xs-app.json as well
-          url: ~{srv-url}
-          forwardAuthToken: true
+      - name: incidents-api
+        group: destinations
+        properties:
+          name: incidents-api # must be used in xs-app.json as well
+          url: ~{srv-url}
+          forwardAuthToken: true
+      - name: feedback-api
+        group: destinations
+        properties:
+          name: feedback-api # must be used in xs-app.json as well
+          url: ~{srv-url}
+          forwardAuthToken: true
       - name: solution-auth
    ...
```




<details>

<summary>Your mta should now look like this</summary>

```yaml
_schema-version: 3.3.0
ID: solution
version: 1.0.0
description: ""
parameters:
  enable-parallel-deployments: true
build-parameters:
  before-all:
    - builder: custom
      commands:
        - npm ci
        - npx cds build ./shared-db --for hana --production --ws-pack
        - npx cds build ./incidents --for nodejs --production --ws-pack
        - npx cds build ./feedback --for nodejs --production --ws-pack
modules:
  - name: incidents-srv
    type: nodejs
    path: incidents/gen/srv
    parameters:
      instances: 1
      buildpack: nodejs_buildpack
      disk-quota: 256M
      memory: 256M
    build-parameters:
      builder: npm
    provides:
      - name: incidents-api # required by consumers of CAP services (e.g. approuter)
        properties:
          srv-url: ${default-url}
    requires:
      - name: solution-auth
      - name: solution-db

  - name: feedback-srv
    type: nodejs
    path: feedback/gen/srv
    parameters:
      instances: 1
      buildpack: nodejs_buildpack
      disk-quota: 256M
      memory: 256M
    build-parameters:
      builder: npm
    provides:
      - name: feedback-api # required by consumers of CAP services (e.g. approuter)
        properties:
          srv-url: ${default-url}
    requires:
      - name: solution-auth
      - name: solution-db

  - name: solution-db-deployer
    type: hdb
    path: shared-db/gen/db
    parameters:
      buildpack: nodejs_buildpack
    requires:
      - name: solution-db

  - name: solution
    type: approuter.nodejs
    path: app/router
    parameters:
      keep-existing-routes: true
      disk-quota: 256M
      memory: 256M
    requires:
      - name: incidents-api
        group: destinations
        properties:
          name: incidents-api # must be used in xs-app.json as well
          url: ~{srv-url}
          forwardAuthToken: true
      - name: feedback-api
        group: destinations
        properties:
          name: feedback-api # must be used in xs-app.json as well
          url: ~{srv-url}
          forwardAuthToken: true
      - name: solution-auth
    provides:
      - name: app-api
        properties:
          app-protocol: ${protocol}
          app-uri: ${default-uri}

resources:
  - name: solution-auth
    type: org.cloudfoundry.managed-service
    parameters:
      service: xsuaa
      service-plan: application
      path: ./xs-security.json
      config:
        xsappname: solution-${org}-${space}
        tenant-mode: dedicated
        oauth2-configuration:
          redirect-uris:
            - https://*~{app-api/app-uri}/**
    requires:
      - name: app-api
  - name: solution-db
    type: com.sap.xs.hdi-container
    parameters:
      service: hana
      service-plan: hdi-shared
```

</details>

## Configure for cloud

👉 Enable both the incidents and feedback app to use xsuaa and hana:

```sh
npm i @sap/xssec --workspace incidents
npm i @sap/xssec --workspace feedback

npm i @cap-js/hana --workspace incidents
npm i @cap-js/hana --workspace feedback
```


👉 Include the incidents ui app in the approuter resources
```sh
mkdir app/router/resources
cd app/router/resources
ln -s ../../../incidents/app/incidents incidents
ln -s ../../../feedback/app/give-feedback give-feedback
cd ../../..
```

The symlink includes the frontend files as static resources to be served.

```
solution
├── app
│   └── router
│       ├── default-env.json
│       ├── package.json
│       ├── resources
│       │   └── incidents -> ../../../incidents/app/incidents
│       └── xs-app.json
└── ...
```

For productive scenarios, ui apps can also be included via build steps or pushed to the html5-apps-repo.

👉 Enter the destinations for each app as well as the static resources in the `xs-app.json`:

```json
{
  "welcomeFile": "incidents/webapp/index.html",

  "routes": [
    {
      "source": "^/odata/v4/admin/(.*)$", 
      "target": "/odata/v4/admin/$1", 
      "destination": "incidents-api", 
      "csrfProtection": true
    },
    {
      "source": "^/odata/v4/processor/(.*)$", 
      "target": "/odata/v4/processor/$1", 
      "destination": "incidents-api", 
      "csrfProtection": true
    },

    {
      "source": "^/odata/v4/feedback/(.*)$", 
      "target": "/odata/v4/feedback/$1", 
      "destination": "feedback-api", 
      "csrfProtection": true
    },

    {
      "source": "^/(.*)$", 
      "target": "$1", 
      "localDir": "resources", 
      "cacheControl": "no-cache, no-store, must-revalidate"
    }
  ]
}
```

## Summary

You now have a fully configured app ready for deployment. The payoff is in the next exercise when we deploy it to Cloud Foundry.

---

[Next Exercise](../05-deploy/)
