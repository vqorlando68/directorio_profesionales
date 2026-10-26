CREATE OR REPLACE PACKAGE BODY uti_manejo_trazas_pkg AS
    /**
     * =========================================================================
     * Paquete     : uti_manejo_trazas_pkg (Body)
     * Propósito   : Implementación técnica de telemetría y trazabilidad
     *               sobre tablas tkr_traza_config, tkr_traza_ejecucion,
     *               tkr_traza_llamado y tkr_traza_estadistica.
     * Estándar    : oracle-plsql-architecture
     * =========================================================================
     */

    -- Función auxiliar para cálculo de duración en milisegundos entre timestamps
    FUNCTION f_calc_duracion_ms (p_inicio IN TIMESTAMP) RETURN NUMBER IS
        v_diff INTERVAL DAY TO SECOND;
    BEGIN
        IF p_inicio IS NULL THEN
            RETURN 0;
        END IF;
        v_diff := SYSTIMESTAMP - p_inicio;
        RETURN ROUND(
            (EXTRACT(DAY FROM v_diff) * 86400000) +
            (EXTRACT(HOUR FROM v_diff) * 3600000) +
            (EXTRACT(MINUTE FROM v_diff) * 60000) +
            (EXTRACT(SECOND FROM v_diff) * 1000),
            3
        );
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END f_calc_duracion_ms;

    -- Procedimiento auxiliar interno para actualizar estadísticas de rendimiento
    PROCEDURE p_actualizar_estadistica (
        p_nombre_paquete IN VARCHAR2,
        p_nombre_metodo  IN VARCHAR2,
        p_es_exito       IN NUMBER,
        p_duracion_ms    IN NUMBER
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_hoy DATE := TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE));
    BEGIN
        MERGE INTO tkr_traza_estadistica s
        USING (
            SELECT p_nombre_paquete AS nombre_paquete,
                   p_nombre_metodo  AS nombre_metodo,
                   v_hoy            AS fecha_periodo
              FROM DUAL
        ) d
        ON (
            s.nombre_paquete = d.nombre_paquete
            AND s.nombre_metodo  = d.nombre_metodo
            AND s.fecha_periodo  = d.fecha_periodo
        )
        WHEN MATCHED THEN
            UPDATE SET
                s.total_ejecuciones      = s.total_ejecuciones + 1,
                s.ejecuciones_exitosas   = s.ejecuciones_exitosas + CASE WHEN p_es_exito = 1 THEN 1 ELSE 0 END,
                s.ejecuciones_fallidas   = s.ejecuciones_fallidas + CASE WHEN p_es_exito = 0 THEN 1 ELSE 0 END,
                s.tiempo_min_ms          = LEAST(s.tiempo_min_ms, NVL(p_duracion_ms, s.tiempo_min_ms)),
                s.tiempo_max_ms          = GREATEST(s.tiempo_max_ms, NVL(p_duracion_ms, s.tiempo_max_ms)),
                s.tiempo_prom_ms         = ROUND(((s.tiempo_prom_ms * s.total_ejecuciones) + NVL(p_duracion_ms, 0)) / (s.total_ejecuciones + 1), 3),
                s.fecha_ultima_ejecucion = CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE),
                s.fecha_modificacion     = CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)
        WHEN NOT MATCHED THEN
            INSERT (
                id,
                nombre_paquete,
                nombre_metodo,
                fecha_periodo,
                total_ejecuciones,
                ejecuciones_exitosas,
                ejecuciones_fallidas,
                tiempo_min_ms,
                tiempo_max_ms,
                tiempo_prom_ms,
                tiempo_p95_ms,
                fecha_ultima_ejecucion,
                estado_registro,
                fecha_creacion,
                fecha_modificacion
            )
            VALUES (
                tkr_traza_estadistica_seq.NEXTVAL,
                p_nombre_paquete,
                p_nombre_metodo,
                v_hoy,
                1,
                CASE WHEN p_es_exito = 1 THEN 1 ELSE 0 END,
                CASE WHEN p_es_exito = 0 THEN 1 ELSE 0 END,
                NVL(p_duracion_ms, 0),
                NVL(p_duracion_ms, 0),
                NVL(p_duracion_ms, 0),
                NVL(p_duracion_ms, 0),
                CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE),
                1,
                CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE),
                CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)
            );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
    END p_actualizar_estadistica;

    -- 1. Evaluar si debe trazar consultando tkr_traza_config
    FUNCTION f_debe_trazar (
        p_nombre_paquete  IN  VARCHAR2,
        p_nombre_metodo   IN  VARCHAR2,
        p_id_usuario      IN  NUMBER   DEFAULT NULL,
        p_id_config_out   OUT NUMBER,
        p_nivel_out       OUT VARCHAR2,
        p_grabar_pay_out  OUT NUMBER
    ) RETURN BOOLEAN IS
        v_hoy DATE := TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE));
    BEGIN
        SELECT c.id,
               c.nivel_detalle,
               c.grabar_payloads
          INTO p_id_config_out,
               p_nivel_out,
               p_grabar_pay_out
          FROM tkr_traza_config c
         WHERE UPPER(c.nombre_paquete) = UPPER(TRIM(p_nombre_paquete))
           AND UPPER(c.nombre_metodo)  = UPPER(TRIM(p_nombre_metodo))
           AND c.es_activo             = 1
           AND c.estado_registro       = 1
           AND (c.id_usuario = p_id_usuario OR c.id_usuario IS NULL)
           AND (c.fecha_desde IS NULL OR v_hoy >= TRUNC(c.fecha_desde))
           AND (c.fecha_hasta IS NULL OR v_hoy <= TRUNC(c.fecha_hasta))
           AND ROWNUM = 1;

        RETURN TRUE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_id_config_out  := NULL;
            p_nivel_out      := 'COMPLETO';
            p_grabar_pay_out := 1;
            RETURN FALSE;
        WHEN OTHERS THEN
            p_id_config_out  := NULL;
            p_nivel_out      := 'COMPLETO';
            p_grabar_pay_out := 1;
            RETURN FALSE;
    END f_debe_trazar;

    -- 2. Iniciar traza (sobrecarga PL/SQL interna)
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
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_codigo_traza VARCHAR2(100) := p_codigo_traza;
        v_id_sesion    VARCHAR2(50)  := SYS_CONTEXT('USERENV', 'SID');
    BEGIN
        IF v_codigo_traza IS NULL THEN
            v_codigo_traza := RAWTOHEX(SYS_GUID());
        END IF;

        SELECT tkr_traza_ejecucion_seq.NEXTVAL
          INTO p_id_ejecucion_out
          FROM DUAL;

        INSERT INTO tkr_traza_ejecucion (
            id,
            id_config,
            id_usuario,
            nombre_paquete,
            nombre_metodo,
            codigo_traza,
            ip_origen,
            id_sesion_oracle,
            fecha_inicio,
            estado,
            json_entrada,
            total_llamados,
            estado_registro,
            fecha_creacion
        ) VALUES (
            p_id_ejecucion_out,
            p_id_config,
            p_id_usuario,
            p_nombre_paquete,
            p_nombre_metodo,
            v_codigo_traza,
            p_ip_origen,
            v_id_sesion,
            CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE),
            'EN_PROCESO',
            CASE WHEN NVL(p_grabar_payload, 1) = 1 THEN p_json_entrada ELSE NULL END,
            0,
            1,
            CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_id_ejecucion_out := NULL;
    END p_iniciar_traza;

    -- 3. Finalizar traza exitosa (sobrecarga PL/SQL interna)
    PROCEDURE p_finalizar_traza (
        p_id_ejecucion       IN  NUMBER,
        p_fecha_inicio       IN  TIMESTAMP,
        p_json_salida        IN  CLOB     DEFAULT NULL,
        p_grabar_payload     IN  NUMBER   DEFAULT 1
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_duracion_ms    NUMBER(12,3);
        v_nombre_paquete VARCHAR2(60);
        v_nombre_metodo  VARCHAR2(60);
    BEGIN
        v_duracion_ms := f_calc_duracion_ms(p_fecha_inicio);

        UPDATE tkr_traza_ejecucion
           SET fecha_fin       = CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE),
               duracion_ms     = v_duracion_ms,
               estado          = 'EXITO',
               json_salida     = CASE WHEN NVL(p_grabar_payload, 1) = 1 THEN p_json_salida ELSE NULL END
         WHERE id = p_id_ejecucion
        RETURNING nombre_paquete, nombre_metodo INTO v_nombre_paquete, v_nombre_metodo;

        COMMIT;

        IF v_nombre_paquete IS NOT NULL THEN
            p_actualizar_estadistica(
                p_nombre_paquete => v_nombre_paquete,
                p_nombre_metodo  => v_nombre_metodo,
                p_es_exito       => 1,
                p_duracion_ms    => v_duracion_ms
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
    END p_finalizar_traza;

    -- 4. Finalizar traza con error (sobrecarga PL/SQL interna)
    PROCEDURE p_finalizar_traza_error (
        p_id_ejecucion       IN  NUMBER,
        p_fecha_inicio       IN  TIMESTAMP,
        p_codigo_error       IN  NUMBER,
        p_mensaje_error      IN  VARCHAR2
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_duracion_ms    NUMBER(12,3);
        v_nombre_paquete VARCHAR2(60);
        v_nombre_metodo  VARCHAR2(60);
    BEGIN
        v_duracion_ms := f_calc_duracion_ms(p_fecha_inicio);

        UPDATE tkr_traza_ejecucion
           SET fecha_fin       = CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE),
               duracion_ms     = v_duracion_ms,
               estado          = 'ERROR',
               codigo_error    = p_codigo_error,
               mensaje_error   = SUBSTR(p_mensaje_error, 1, 4000)
         WHERE id = p_id_ejecucion
        RETURNING nombre_paquete, nombre_metodo INTO v_nombre_paquete, v_nombre_metodo;

        COMMIT;

        IF v_nombre_paquete IS NOT NULL THEN
            p_actualizar_estadistica(
                p_nombre_paquete => v_nombre_paquete,
                p_nombre_metodo  => v_nombre_metodo,
                p_es_exito       => 0,
                p_duracion_ms    => v_duracion_ms
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
    END p_finalizar_traza_error;

    -- 5. Registrar sub-llamado / span en tkr_traza_llamado
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
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_id_llamado   NUMBER(12);
        v_orden        NUMBER(6);
    BEGIN
        SELECT NVL(MAX(orden_llamado), 0) + 1
          INTO v_orden
          FROM tkr_traza_llamado
         WHERE id_ejecucion = p_id_ejecucion;

        SELECT tkr_traza_llamado_seq.NEXTVAL
          INTO v_id_llamado
          FROM DUAL;

        INSERT INTO tkr_traza_llamado (
            id,
            id_ejecucion,
            id_llamado_padre,
            orden_llamado,
            tipo_llamado,
            paquete_llamado,
            metodo_llamado,
            parametros_enviados,
            parametros_recibidos,
            fecha_inicio,
            fecha_fin,
            duracion_ms,
            estado,
            codigo_error,
            mensaje_error,
            estado_registro,
            fecha_creacion
        ) VALUES (
            v_id_llamado,
            p_id_ejecucion,
            p_id_llamado_padre,
            v_orden,
            NVL(p_tipo_llamado, 'PLSQL_SUBPROGRAM'),
            p_paquete_llamado,
            p_metodo_llamado,
            p_parametros_enviados,
            p_parametros_recibidos,
            CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE),
            CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE),
            p_duracion_ms,
            NVL(p_estado, 'EXITO'),
            p_codigo_error,
            p_mensaje_error,
            1,
            CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)
        );

        UPDATE tkr_traza_ejecucion
           SET total_llamados = NVL(total_llamados, 0) + 1
         WHERE id = p_id_ejecucion;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
    END p_registrar_llamado;

    -- 6. Endpoint Frontend: Iniciar traza vía payload JSON
    PROCEDURE p_iniciar_traza (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_obj_in           JSON_OBJECT_T;
        v_nombre_paquete   VARCHAR2(60);
        v_nombre_metodo    VARCHAR2(60);
        v_id_usuario       NUMBER(12);
        v_codigo_traza     VARCHAR2(100);
        v_ip_origen        VARCHAR2(50);
        v_payload          CLOB;
        v_id_ejecucion     NUMBER(12);
    BEGIN
        IF p_json_entrada IS NULL THEN
            SELECT JSON_OBJECT('codigo' VALUE -20001, 'error' VALUE -20001, 'mensaje' VALUE 'Payload requerido' RETURNING CLOB) INTO p_json_salida FROM DUAL;
            RETURN;
        END IF;

        v_obj_in := JSON_OBJECT_T.parse(p_json_entrada);
        v_nombre_paquete := v_obj_in.get_string('nombre_paquete');
        v_nombre_metodo  := v_obj_in.get_string('nombre_metodo');

        IF v_obj_in.has('id_usuario') THEN
            v_id_usuario := v_obj_in.get_number('id_usuario');
        END IF;
        IF v_obj_in.has('codigo_traza') THEN
            v_codigo_traza := v_obj_in.get_string('codigo_traza');
        END IF;
        IF v_obj_in.has('direccion_ip') THEN
            v_ip_origen := v_obj_in.get_string('direccion_ip');
        END IF;
        IF v_obj_in.has('payload') THEN
            v_payload := v_obj_in.get_clob('payload');
        END IF;

        p_iniciar_traza(
            p_nombre_paquete   => v_nombre_paquete,
            p_nombre_metodo    => v_nombre_metodo,
            p_id_usuario       => v_id_usuario,
            p_codigo_traza     => v_codigo_traza,
            p_ip_origen        => v_ip_origen,
            p_json_entrada     => v_payload,
            p_grabar_payload   => 1,
            p_id_ejecucion_out => v_id_ejecucion
        );

        SELECT JSON_OBJECT(
                   'codigo'  VALUE 0,
                   'mensaje' VALUE 'Traza iniciada exitosamente',
                   'datos'   VALUE JSON_OBJECT(
                                       'id_ejecucion' VALUE v_id_ejecucion,
                                       'codigo_traza' VALUE v_codigo_traza
                                   )
                   RETURNING CLOB
               )
          INTO p_json_salida
          FROM DUAL;
    EXCEPTION
        WHEN OTHERS THEN
            DECLARE
                v_err VARCHAR2(4000) := SQLERRM;
            BEGIN
                SELECT JSON_OBJECT('codigo' VALUE -20000, 'error' VALUE -20000, 'mensaje' VALUE 'Error al iniciar traza: ' || v_err RETURNING CLOB) INTO p_json_salida FROM DUAL;
            END;
    END p_iniciar_traza;

    -- 7. Endpoint Frontend: Finalizar traza vía payload JSON
    PROCEDURE p_finalizar_traza (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_obj_in       JSON_OBJECT_T;
        v_id_ejecucion NUMBER(12);
        v_estado       VARCHAR2(20) := 'EXITO';
        v_codigo_error NUMBER(10);
        v_mensaje_err  VARCHAR2(4000);
        v_payload      CLOB;
        v_inicio       TIMESTAMP := SYSTIMESTAMP;
    BEGIN
        IF p_json_entrada IS NULL THEN
            SELECT JSON_OBJECT('codigo' VALUE -20001, 'error' VALUE -20001, 'mensaje' VALUE 'Payload requerido' RETURNING CLOB) INTO p_json_salida FROM DUAL;
            RETURN;
        END IF;

        v_obj_in := JSON_OBJECT_T.parse(p_json_entrada);
        v_id_ejecucion := v_obj_in.get_number('id_ejecucion');

        IF v_obj_in.has('estado') THEN
            v_estado := UPPER(TRIM(v_obj_in.get_string('estado')));
        END IF;
        IF v_obj_in.has('payload') THEN
            v_payload := v_obj_in.get_clob('payload');
        END IF;
        IF v_obj_in.has('codigo_error') THEN
            v_codigo_error := v_obj_in.get_number('codigo_error');
        END IF;
        IF v_obj_in.has('mensaje_error') THEN
            v_mensaje_err := v_obj_in.get_string('mensaje_error');
        END IF;

        IF v_estado = 'ERROR' THEN
            p_finalizar_traza_error(
                p_id_ejecucion  => v_id_ejecucion,
                p_fecha_inicio  => v_inicio,
                p_codigo_error  => v_codigo_error,
                p_mensaje_error => v_mensaje_err
            );
        ELSE
            p_finalizar_traza(
                p_id_ejecucion   => v_id_ejecucion,
                p_fecha_inicio   => v_inicio,
                p_json_salida    => v_payload,
                p_grabar_payload => 1
            );
        END IF;

        SELECT JSON_OBJECT(
                   'codigo'  VALUE 0,
                   'mensaje' VALUE 'Traza finalizada exitosamente',
                   'datos'   VALUE JSON_OBJECT('id_ejecucion' VALUE v_id_ejecucion)
                   RETURNING CLOB
               )
          INTO p_json_salida
          FROM DUAL;
    EXCEPTION
        WHEN OTHERS THEN
            DECLARE
                v_err VARCHAR2(4000) := SQLERRM;
            BEGIN
                SELECT JSON_OBJECT('codigo' VALUE -20000, 'error' VALUE -20000, 'mensaje' VALUE 'Error al finalizar traza: ' || v_err RETURNING CLOB) INTO p_json_salida FROM DUAL;
            END;
    END p_finalizar_traza;

    -- 8. Endpoint Frontend: Configurar regla de telemetría dinámica
    PROCEDURE p_configurar_regla (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_obj_in         JSON_OBJECT_T;
        v_nombre_paquete VARCHAR2(60);
        v_nombre_metodo  VARCHAR2(60);
        v_id_usuario     NUMBER(12);
        v_nivel_detalle  VARCHAR2(30) := 'COMPLETO';
        v_grabar_payload NUMBER(1) := 1;
        v_es_activo      NUMBER(1) := 1;
        v_descripcion    VARCHAR2(500);
        v_id_config      NUMBER(12);
    BEGIN
        IF p_json_entrada IS NULL THEN
            SELECT JSON_OBJECT('codigo' VALUE -20001, 'error' VALUE -20001, 'mensaje' VALUE 'Payload requerido' RETURNING CLOB) INTO p_json_salida FROM DUAL;
            RETURN;
        END IF;

        v_obj_in := JSON_OBJECT_T.parse(p_json_entrada);
        v_nombre_paquete := v_obj_in.get_string('nombre_paquete');
        v_nombre_metodo  := v_obj_in.get_string('nombre_metodo');

        IF v_obj_in.has('id_usuario') THEN
            v_id_usuario := v_obj_in.get_number('id_usuario');
        END IF;
        IF v_obj_in.has('nivel_detalle') THEN
            v_nivel_detalle := v_obj_in.get_string('nivel_detalle');
        END IF;
        IF v_obj_in.has('grabar_payloads') THEN
            v_grabar_payload := v_obj_in.get_number('grabar_payloads');
        END IF;
        IF v_obj_in.has('es_activo') THEN
            v_es_activo := v_obj_in.get_number('es_activo');
        END IF;
        IF v_obj_in.has('descripcion') THEN
            v_descripcion := v_obj_in.get_string('descripcion');
        END IF;

        MERGE INTO tkr_traza_config c
        USING (
            SELECT v_nombre_paquete AS nombre_paquete,
                   v_nombre_metodo  AS nombre_metodo,
                   v_id_usuario     AS id_usuario
              FROM DUAL
        ) d
        ON (
            c.nombre_paquete = d.nombre_paquete
            AND c.nombre_metodo = d.nombre_metodo
            AND (c.id_usuario = d.id_usuario OR (c.id_usuario IS NULL AND d.id_usuario IS NULL))
        )
        WHEN MATCHED THEN
            UPDATE SET
                c.nivel_detalle      = v_nivel_detalle,
                c.grabar_payloads    = v_grabar_payload,
                c.es_activo          = v_es_activo,
                c.descripcion        = v_descripcion,
                c.fecha_modificacion = CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)
        WHEN NOT MATCHED THEN
            INSERT (
                id,
                nombre_paquete,
                nombre_metodo,
                id_usuario,
                nivel_detalle,
                grabar_payloads,
                es_activo,
                descripcion,
                estado_registro,
                fecha_creacion,
                fecha_modificacion
            )
            VALUES (
                tkr_traza_config_seq.NEXTVAL,
                v_nombre_paquete,
                v_nombre_metodo,
                v_id_usuario,
                v_nivel_detalle,
                v_grabar_payload,
                v_es_activo,
                v_descripcion,
                1,
                CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE),
                CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)
            );

        SELECT JSON_OBJECT(
                   'codigo'  VALUE 0,
                   'mensaje' VALUE 'Regla de telemetría configurada exitosamente'
                   RETURNING CLOB
               )
          INTO p_json_salida
          FROM DUAL;
    EXCEPTION
        WHEN OTHERS THEN
            DECLARE
                v_err VARCHAR2(4000) := SQLERRM;
            BEGIN
                SELECT JSON_OBJECT('codigo' VALUE -20000, 'error' VALUE -20000, 'mensaje' VALUE 'Error al configurar regla: ' || v_err RETURNING CLOB) INTO p_json_salida FROM DUAL;
            END;
    END p_configurar_regla;

    -- 9. Endpoint Frontend: Consultar trazas recientes
    PROCEDURE p_consultar_trazas (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_json_arr CLOB;
    BEGIN
        SELECT COALESCE(
                   JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'id'               VALUE e.id,
                           'nombre_paquete'   VALUE e.nombre_paquete,
                           'nombre_metodo'    VALUE e.nombre_metodo,
                           'codigo_traza'     VALUE e.codigo_traza,
                           'id_usuario'       VALUE e.id_usuario,
                           'ip_origen'        VALUE e.ip_origen,
                           'fecha_inicio'     VALUE TO_CHAR(e.fecha_inicio, 'YYYY-MM-DD HH24:MI:SS'),
                           'fecha_fin'        VALUE TO_CHAR(e.fecha_fin, 'YYYY-MM-DD HH24:MI:SS'),
                           'duracion_ms'      VALUE e.duracion_ms,
                           'estado'           VALUE e.estado,
                           'codigo_error'     VALUE e.codigo_error,
                           'mensaje_error'    VALUE e.mensaje_error,
                           'total_llamados'   VALUE e.total_llamados
                       )
                       ORDER BY e.id DESC
                       RETURNING CLOB
                   ),
                   TO_CLOB('[]')
               )
          INTO v_json_arr
          FROM (
              SELECT *
                FROM tkr_traza_ejecucion
               ORDER BY id DESC
               FETCH FIRST 50 ROWS ONLY
          ) e;

        SELECT JSON_OBJECT(
                   'codigo'  VALUE 0,
                   'mensaje' VALUE 'Trazas consultadas exitosamente',
                   'trazas'  VALUE JSON_QUERY(v_json_arr, '$' RETURNING CLOB)
                   RETURNING CLOB
               )
          INTO p_json_salida
          FROM DUAL;
    EXCEPTION
        WHEN OTHERS THEN
            DECLARE
                v_err VARCHAR2(4000) := SQLERRM;
            BEGIN
                SELECT JSON_OBJECT('codigo' VALUE -20000, 'error' VALUE -20000, 'mensaje' VALUE 'Error al consultar trazas: ' || v_err RETURNING CLOB) INTO p_json_salida FROM DUAL;
            END;
    END p_consultar_trazas;

END uti_manejo_trazas_pkg;
/
