# MCPサーバー.md

## 目的

Snowflake側のMCPサーバーは、通常のPython/Nodeサーバープロセスではなく、Snowflake内に作成する **Snowflake-managed MCP server object** です。したがって、見本コードはSnowflakeで実行するSQLです。

この見本では、まず安全な最小構成としてCortex AnalystとCortex Searchを公開します。`SYSTEM_EXECUTE_SQL`は強力なので、Private接続かつ読み取り専用roleでの検証用途に限定してください。

## 1. 会社環境で置き換える値

```text
<DATABASE>              例: MCP_DB
<SCHEMA>                例: MCP_SCHEMA
<WAREHOUSE>             例: MCP_WH
<MCP_SERVER_NAME>       例: company_mcp_server
<MCP_ADMIN_ROLE>        例: MCP_ADMIN_ROLE
<MCP_ACCESS_ROLE>       例: MCP_ACCESS_ROLE
<SEMANTIC_VIEW>         例: SALES_SEMANTIC_VIEW
<SEARCH_SERVICE>        例: DOC_SEARCH_SERVICE
<CORTEX_AGENT>          例: BUSINESS_AGENT
<FUNCTION_NAME>         例: SAFE_LOOKUP_FUNCTION
<PROCEDURE_NAME>        例: SAFE_REPORT_PROCEDURE
```

## 2. Roleと基本権限の見本

```sql
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS <MCP_ADMIN_ROLE>;
CREATE ROLE IF NOT EXISTS <MCP_ACCESS_ROLE>;

-- 実際の利用ユーザーに付与する
GRANT ROLE <MCP_ACCESS_ROLE> TO USER <USERNAME>;

-- 管理者にMCP作成roleを付与する
GRANT ROLE <MCP_ADMIN_ROLE> TO USER <ADMIN_USERNAME>;
```

```sql
USE ROLE ACCOUNTADMIN;

-- Database / Schema / Warehouse
GRANT USAGE ON DATABASE <DATABASE> TO ROLE <MCP_ADMIN_ROLE>;
GRANT USAGE ON SCHEMA <DATABASE>.<SCHEMA> TO ROLE <MCP_ADMIN_ROLE>;
GRANT CREATE MCP SERVER ON SCHEMA <DATABASE>.<SCHEMA> TO ROLE <MCP_ADMIN_ROLE>;

GRANT USAGE ON DATABASE <DATABASE> TO ROLE <MCP_ACCESS_ROLE>;
GRANT USAGE ON SCHEMA <DATABASE>.<SCHEMA> TO ROLE <MCP_ACCESS_ROLE>;
GRANT USAGE ON WAREHOUSE <WAREHOUSE> TO ROLE <MCP_ACCESS_ROLE>;

-- Cortex Analyst用
GRANT SELECT ON SEMANTIC VIEW <DATABASE>.<SCHEMA>.<SEMANTIC_VIEW>
  TO ROLE <MCP_ACCESS_ROLE>;

-- Cortex Search用
GRANT USAGE ON CORTEX SEARCH SERVICE <DATABASE>.<SCHEMA>.<SEARCH_SERVICE>
  TO ROLE <MCP_ACCESS_ROLE>;

-- Cortex Agent用。使わない場合は不要
GRANT USAGE ON CORTEX AGENT <DATABASE>.<SCHEMA>.<CORTEX_AGENT>
  TO ROLE <MCP_ACCESS_ROLE>;
```

接続ユーザーのdefault role/warehouseも設定します。

```sql
ALTER USER <USERNAME>
  SET DEFAULT_ROLE = '<MCP_ACCESS_ROLE>'
      DEFAULT_WAREHOUSE = '<WAREHOUSE>';
```

## 3. 最小MCP server作成コード

Cortex AnalystとCortex Searchだけを公開する基本形です。

```sql
USE ROLE <MCP_ADMIN_ROLE>;
USE DATABASE <DATABASE>;
USE SCHEMA <SCHEMA>;

CREATE OR REPLACE MCP SERVER <MCP_SERVER_NAME>
  FROM SPECIFICATION $$
    tools:
      - name: "business-analyst"
        type: "CORTEX_ANALYST_MESSAGE"
        identifier: "<DATABASE>.<SCHEMA>.<SEMANTIC_VIEW>"
        title: "Business Analyst"
        description: "Governed semantic analysis for approved business data."

      - name: "document-search"
        type: "CORTEX_SEARCH_SERVICE_QUERY"
        identifier: "<DATABASE>.<SCHEMA>.<SEARCH_SERVICE>"
        title: "Document Search"
        description: "Searches approved business documents through Cortex Search."
  $$;
```

作成したMCP serverへの利用権限を付与します。

```sql
GRANT USAGE ON MCP SERVER <DATABASE>.<SCHEMA>.<MCP_SERVER_NAME>
  TO ROLE <MCP_ACCESS_ROLE>;
```

## 4. Cortex Agent toolを追加する場合

```sql
CREATE OR REPLACE MCP SERVER <MCP_SERVER_NAME>
  FROM SPECIFICATION $$
    tools:
      - name: "business-agent"
        type: "CORTEX_AGENT_RUN"
        identifier: "<DATABASE>.<SCHEMA>.<CORTEX_AGENT>"
        title: "Business Agent"
        description: "Runs an approved Cortex Agent for business questions."
  $$;
```

## 5. SQL実行toolを追加する場合

`SYSTEM_EXECUTE_SQL`は便利ですが、自然言語からSQLを実行できる入口になります。原則としてPrivate接続、検証用途、読み取り専用roleに限定してください。

```sql
CREATE OR REPLACE MCP SERVER <MCP_SERVER_NAME>_sql_private
  FROM SPECIFICATION $$
    tools:
      - name: "sql-readonly"
        type: "SYSTEM_EXECUTE_SQL"
        title: "SQL Read Only"
        description: "Executes SQL only for private validation with a least-privileged read-only role."
  $$;

GRANT USAGE ON MCP SERVER <DATABASE>.<SCHEMA>.<MCP_SERVER_NAME>_sql_private
  TO ROLE <MCP_ACCESS_ROLE>;
```

## 6. UDF / Stored ProcedureをGENERIC toolとして公開する場合

UDFの例です。

```sql
GRANT USAGE ON FUNCTION <DATABASE>.<SCHEMA>.<FUNCTION_NAME>(NUMBER)
  TO ROLE <MCP_ACCESS_ROLE>;

CREATE OR REPLACE MCP SERVER <MCP_SERVER_NAME>_generic_fn
  FROM SPECIFICATION $$
    tools:
      - name: "safe-lookup"
        type: "GENERIC"
        identifier: "<DATABASE>.<SCHEMA>.<FUNCTION_NAME>"
        title: "Safe Lookup"
        description: "Runs an approved UDF with a restricted input schema."
        config:
          type: "function"
          warehouse: "<WAREHOUSE>"
          input_schema:
            type: "object"
            properties:
              id:
                description: "Numeric lookup id"
                type: "number"
            required:
              - id
  $$;
```

Stored Procedureの例です。

```sql
GRANT USAGE ON PROCEDURE <DATABASE>.<SCHEMA>.<PROCEDURE_NAME>(NUMBER, NUMBER)
  TO ROLE <MCP_ACCESS_ROLE>;

CREATE OR REPLACE MCP SERVER <MCP_SERVER_NAME>_generic_sp
  FROM SPECIFICATION $$
    tools:
      - name: "safe-report"
        type: "GENERIC"
        identifier: "<DATABASE>.<SCHEMA>.<PROCEDURE_NAME>"
        title: "Safe Report"
        description: "Runs an approved stored procedure with fixed parameters."
        config:
          type: "procedure"
          warehouse: "<WAREHOUSE>"
          input_schema:
            type: "object"
            properties:
              start_id:
                description: "Start id"
                type: "number"
              end_id:
                description: "End id"
                type: "number"
            required:
              - start_id
              - end_id
  $$;
```

## 7. 確認コマンド

```sql
SHOW MCP SERVERS IN SCHEMA <DATABASE>.<SCHEMA>;

DESCRIBE MCP SERVER <DATABASE>.<SCHEMA>.<MCP_SERVER_NAME>;
```

MCP endpoint URLは次の形式です。

```text
https://<account_url>/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER_NAME>
```

Private接続では`<account_url>`にPrivate Link用URLを使います。

```text
https://<ORG>-<ACCOUNT>.privatelink.snowflakecomputing.com/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER_NAME>
```

Public接続では通常のpublic account URLを使います。

```text
https://<ORG>-<ACCOUNT>.snowflakecomputing.com/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER_NAME>
```

## 8. 注意

- `title`、`description`、tool名はSnowflake metadataとして見えるため、個人情報・機密名・内部コード名を書かないでください。
- MCP serverへの`USAGE`だけではtool実行権限は足りません。Semantic View、Cortex Search、Cortex Agent、UDF/SP、Warehouseへ個別に権限が必要です。
- hostnameにはアンダースコアではなくハイフンを使います。
- Public向けMCP serverには`SYSTEM_EXECUTE_SQL`を入れない方針を推奨します。

## 参照元

- [Snowflake CREATE MCP SERVER](https://docs.snowflake.com/en/sql-reference/sql/create-mcp-server)
- [Snowflake-managed MCP server](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp)

