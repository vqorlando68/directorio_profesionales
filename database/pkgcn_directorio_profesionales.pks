CREATE OR REPLACE PACKAGE pkgcn_directorio_profesionales AS
    /*
    || =========================================================================
    || Paquete: pkgcn_directorio_profesionales
    || Propósito: Capa Multi-Tabla de Consultas Relacionales y DML Multi-Tabla
    ||            para el Directorio de Profesionales de la Salud.
    || Estándar: oracle-plsql-architecture
    || Responsabilidades:
    ||   - Recibe siempre un payload JSON (p_json_entrada) y evalúa los filtros
    ||     en las sentencias DML/SQL directamente mediante JSON_VALUE.
    ||   - Consultas multi-tabla con sintaxis relacional tradicional Oracle (+).
    ||   - Búsqueda relacional de profesionales habilitados con paginación.
    ||   - Consulta relacional multi-tabla de turnos y franjas horarias.
    ||   - Consulta relacional de catálogos maestros.
    ||   - CERO LÓGICA DE NEGOCIO: La orquestación y las reglas de dominio
    ||     residen exclusivamente en pkgln_directorio_profesionales.
    ||   - CERO CONTROL TRANSACCIONAL: p_do_commit y ROLLBACK gobernados por pkgln_.
    || =========================================================================
    */

    -- 1. Consultar directorio paginado de profesionales habilitados con filtros multi-tabla
    PROCEDURE p_consultar_profesionales_json (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 2. Consultar turnos multi-tabla de un profesional para un día de la semana
    FUNCTION f_consultar_turnos (
        p_json_entrada IN CLOB
    ) RETURN SYS_REFCURSOR;

    -- 3. Consultar catálogos para filtros del directorio (especialidades, convenios, aseguramientos)
    PROCEDURE p_consultar_filtros_catalogo_json (
        p_json_entrada IN  CLOB DEFAULT NULL,
        p_json_salida  OUT CLOB
    );

    -- 4. Consultar información detallada del profesional seleccionado
    PROCEDURE p_consultar_detalle_profesional (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 5. Consultar los días de la semana (LU, MA, MI...) con horario activo para un profesional en un rango de fechas
    FUNCTION f_dias_servicio_profesional (
        p_id_usuario   IN NUMBER,
        p_fecha_inicio IN VARCHAR2 DEFAULT NULL,
        p_fecha_fin    IN VARCHAR2 DEFAULT NULL,
        p_id_convenio  IN NUMBER DEFAULT NULL,
        p_id_aseg      IN NUMBER DEFAULT NULL
    ) RETURN VARCHAR2;

END pkgcn_directorio_profesionales;
/
