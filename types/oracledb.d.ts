declare module 'oracledb' {
  export interface Connection {
    execute<T = any>(sql: string, binds?: any, options?: any): Promise<any>;
    close(): Promise<void>;
  }

  export type BindParameters = Record<string, any> | any[];

  export const CLOB: any;
  export const BIND_IN: any;
  export const BIND_OUT: any;
  export let autoCommit: boolean;
  export let fetchAsString: any[];
  export function getConnection(config: any): Promise<Connection>;

  const oracledb: {
    getConnection(config: any): Promise<Connection>;
    autoCommit: boolean;
    fetchAsString: any[];
    CLOB: any;
    BIND_IN: any;
    BIND_OUT: any;
    [key: string]: any;
  };

  export default oracledb;
}
