CREATE OR REPLACE PACKAGE uti_manejo_trazas_pkg AS
    /**
     * =========================================================================
     * Paquete     : uti_manejo_trazas_pkg
     * Propósito   : Paquete transversal para la gestión integral de telemetría y
     *               trazabilidad del sistema (tkr_traza_config, tkr_traza_ejecucion,
     *               tkr_traza_llamado, tkr_traza_estadistica).
     * Estándar    : oracle-plsql-architecture
     * =========================================================================
     */

    -- -------------------------------------------------------------------------
    -- MÉTODOS PL/SQL INTERNOS PARA CONSUMO DESDE ORQUESTADORES pkgln_
    -- -------------------------------------------------------------------------

    /**
     * Evalúa si un objeto debe ser trazado consultando la tabla tkr_traza_config
     * por paquete, método y usuario ejecutor.
     */
    FUNCTION f_debe_trazar (
        p_nombre_paquete  IN  VARCHAR2,
        p_nombre_metodo   IN  VARCHAR2,
        p_id_usuario      IN  NUMBER   DEFAULT NULL,
        p_id_config_out   OUT NUMBER,
        p_nivel_out       OUT VARCHAR2,
        p_grabar_pay_out  OUT NUMBER
    ) RETURN BOOLEAN;

    /**
     * Inicia una traza de ejecución de forma autónoma (PRAGMA AUTONOMOUS_TRANSACTION)
     * e inserta en tkr_traza_ejecucion con estado 'EN_PROCESO'.
     */
    PROCEDURE p_iniciar_traza (
        p_nombre_paquete     IN  VARCHAR2,
        p_nombre_metodo      IN  VARCHAR2,
        p_id_config          IN  NUMBER   DEFAULT NULL,
        p_id_usuario         IN  NUMBER   DEFAULT NULL,
        p_codigo_traza       IN  VARCHAR2 DEFAULT NULL,
        p_ip_origen          IN  VARCHAR2 DEFAULT NULL,
        p_json_entrada       IN  CLOB     DEFAULT NULL,
        p_grabar_payload     IN  NUMBER   DEFAULT 1,
        p_id_ejecucion_out   OUT NUMBER
    );

    /**
     * Cierra exitosamente una traza de ejecución de forma autónoma.
     * Actualiza tkr_traza_ejecucion con estado 'EXITO', fecha_fin y duracion_ms,
     * y actualiza métricas acumuladas en tkr_traza_estadistica.
     */
    PROCEDURE p_finalizar_traza (
        p_id_ejecucion       IN  NUMBER,
        p_fecha_inicio       IN  TIMESTAMP,
        p_json_salida        IN  CLOB     DEFAULT NULL,
        p_grabar_payload     IN  NUMBER   DEFAULT 1
    );

    /**
     * Cierra con estado 'ERROR' una traza de ejecución de forma autónoma.
     * Actualiza tkr_traza_ejecucion con estado 'ERROR', SQLCODE y SQLERRM,
     * y actualiza métricas acumuladas en tkr_traza_estadistica.
     */
    PROCEDURE p_finalizar_traza_error (
        p_id_ejecucion       IN  NUMBER,
        p_fecha_inicio       IN  TIMESTAMP,
        p_codigo_error       IN  NUMBER,
        p_mensaje_error      IN  VARCHAR2
    );

    /**
     * Registra un sub-llamado / span en tkr_traza_llamado.
     */
    PROCEDURE p_registrar_llamado (
        p_id_ejecucion        IN  NUMBER,
        p_paquete_llamado     IN  VARCHAR2,
        p_metodo_llamado      IN  VARCHAR2,
        p_tipo_llamado        IN  VARCHAR2 DEFAULT 'PLSQL_SUBPROGRAM',
        p_parametros_enviados IN  CLOB     DEFAULT NULL,
        p_parametros_recibidos IN CLOB     DEFAULT NULL,
        p_duracion_ms         IN  NUMBER   DEFAULT NULL,
        p_estado              IN  VARCHAR2 DEFAULT 'EXITO',
        p_codigo_error        IN  NUMBER   DEFAULT NULL,
        p_mensaje_error       IN  VARCHAR2 DEFAULT NULL,
        p_id_llamado_padre    IN  NUMBER   DEFAULT NULL
    );

    -- -------------------------------------------------------------------------
    -- ENDPOINTS FORMALES TIPO pkgln_ (Firma CLOB IN / OUT para Frontend / APIs)
    -- -------------------------------------------------------------------------

    PROCEDURE p_iniciar_traza (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    PROCEDURE p_finalizar_traza (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    PROCEDURE p_configurar_regla (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    PROCEDURE p_consultar_trazas (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

END uti_manejo_trazas_pkg;
/
