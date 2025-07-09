# Exercise 03 - A shared database

In the previous exercise, we have been running the whole solution together. So locally we already have a shared database in memory.
Let's now also create a module for deploying the combined database artifacts to a persistent database.

> Continue inside the `solution` folder. If you have a running application, you can stop it.

👉 Add a `shared-db` module

```sh
cds init shared-db --add hana
```

Again, this is located parallel to our other projects and registered as npm workspace due to our wildcard configuration.

```
solution
├── feedback
├── incidents
├── node_modules
├── shared-db
├── srv
├── package-lock.json
└── package.json
```

You may also notice the `srv` folder that we created in the previous exercise. This is not considered as a workspace, because it does not have a `package.json`.

👉 Install node modules
```sh
npm i
```

👉 Add our application modules as dependencies
```sh
npm add --workspace shared-db @capire/incidents
npm add --workspace shared-db feedback
```

These now appear in the `shared-db/package.json`.

👉 Add a `shared-db/db/schema.cds`

```cds
using from '@capire/incidents';
using from 'feedback';
```

You may notice that this is exactly the same as we've done for running the solution together locally.
It combines the cds models of both incidents and feedback. In this case not for the services, but for the database artifacts.

If we want tighter control over what we use, we could also import from a specific directory like `@capire/incidents/db` (provided there is an `index.cds` in there) or from a specific file like `@capire/incidents/db/schema`.
There are scenarios though where the features defined in `srv` can modify what is needed on persistence level. A prominent example of this is the `@odata.draft.enabled` annotation. This is why by default both the `db` and `srv` folder are considered during `cds build --for hana`.

👉 Try it out
```sh
cds compile shared-db/db -2 hana
```

This compiles the cds model we just defined into ddl statements which can be used to initialize a HANA database with corresponding tables.
The tables should include our model from both incidents and feedback.

```sql
...
----- sap.capire.incidents.Incidents.hdbtable -----
COLUMN TABLE sap_capire_incidents_Incidents (
  ID NVARCHAR(36) NOT NULL,
  createdAt TIMESTAMP,
  createdBy NVARCHAR(255),
  modifiedAt TIMESTAMP,
  modifiedBy NVARCHAR(255),
  customer_ID NVARCHAR(5000),
  title NVARCHAR(5000),
  urgency_code NVARCHAR(5000) DEFAULT 'M',
  status_code NVARCHAR(5000) DEFAULT 'N',
  PRIMARY KEY(ID)
)
...
----- solution.feedback.Feedback.hdbtable -----
COLUMN TABLE solution_feedback_Feedback (
  ID NVARCHAR(36) NOT NULL,
  subject NVARCHAR(5000),
  "USER" NVARCHAR(255),
  responsiveness INTEGER,
  quality INTEGER,
  helpfulness INTEGER,
  comment NVARCHAR(200),
  PRIMARY KEY(ID)
)
...
```




## Further reading

- [Using a shared database](https://cap.cloud.sap/docs/guides/deployment/microservices#using-a-shared-database)

---

[Next Exercise](../04-deployment-configuration/)
