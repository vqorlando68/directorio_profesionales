import oracledb from 'oracledb';

try {
  oracledb.autoCommit = true;
  oracledb.fetchAsString = [oracledb.CLOB];
} catch (err) {
  console.warn('Configuración de oracledb:', err);
}

export interface OracleConfig {
  user: string;
  password: string;
  connectString: string;
}

export function getOracleConfig(): OracleConfig {
  const user = process.env.ORACLE_DB_USER || 'TEKER_DEV';
  let password = process.env.ORACLE_DB_PASSWORD || 'T3k3r_2025_D3v_$ecur3';

  if (password === 'T3k3r_2025_D3v_' || !password.includes('$ecur3')) {
    password = 'T3k3r_2025_D3v_$ecur3';
  }
  if (password.includes('\\$')) {
    password = password.replace('\\$', '$');
  }

  const connectString = process.env.ORACLE_DB_CONNECTION_STRING || 'tekerapp-db.maxapex.net:1521/orclpdb1';

  return { user, password, connectString };
}

export async function getDbConnection(): Promise<any> {
  const config = getOracleConfig();
  return await oracledb.getConnection(config);
}

export async function executePlsqlJson(procedureCall: string, payload: any): Promise<any> {
  let connection;
  try {
    connection = await getDbConnection();
    const jsonInput = typeof payload === 'string' ? payload : JSON.stringify(payload);

    const result = await connection.execute(
      `BEGIN ${procedureCall}(:p_json_entrada, :p_json_salida); END;`,
      {
        p_json_entrada: { val: jsonInput, dir: oracledb.BIND_IN, type: oracledb.CLOB },
        p_json_salida: { dir: oracledb.BIND_OUT, type: oracledb.CLOB }
      }
    );

    const rawOutput = result.outBinds?.p_json_salida;
    let textOutput = '';
    if (rawOutput) {
      if (typeof rawOutput === 'string') {
        textOutput = rawOutput;
      } else if (typeof rawOutput.getData === 'function') {
        textOutput = await rawOutput.getData();
      } else {
        textOutput = String(rawOutput);
      }
    }

    if (!textOutput) {
      return { codigo: 0, mensaje: 'Sin respuesta del procedimiento' };
    }

    return JSON.parse(textOutput);
  } finally {
    if (connection) {
      try {
        await connection.close();
      } catch (closeErr) {
        console.error('Error al cerrar conexión Oracle:', closeErr);
      }
    }
  }
}
