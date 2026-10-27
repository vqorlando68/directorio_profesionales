CREATE OR REPLACE PACKAGE BODY pkgln_directorio_profesionales AS
    /*
    || =========================================================================
    || Paquete: pkgln_directorio_profesionales (Body)
    || Propósito: Orquestador transaccional con gobierno de excepciones, telemetría
    ||            y construcción de payloads JSON puramente en memoria con
    ||            JSON_OBJECT_T (CERO sentencias DML para armar JSON).
    || Estándar: oracle-plsql-architecture
    || =========================================================================
    */

    vro_error tkr_errores%ROWTYPE;

    -- 1. Consultar directorio paginado de profesionales habilitados con filtros
    PROCEDURE p_consultar_directorio (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_obj_in                JSON_OBJECT_T;
        v_id_usuario_ejecutor   NUMBER(12);
        v_codigo_traza          VARCHAR2(100);
        v_ip_origen             VARCHAR2(50);
        
        -- Filtros
        v_id_especialidad       NUMBER(12);
        v_id_convenio           NUMBER(12);
        v_id_tipo_aseguramiento NUMBER(12);
        v_modalidad             VARCHAR2(10);
        v_busqueda              VARCHAR2(200);
        v_pagina                NUMBER := 1;
        v_registros_pagina      NUMBER := 12;

        -- Telemetría
        v_traza_activa          BOOLEAN := FALSE;
        v_id_config_traza       NUMBER(12) := NULL;
        v_id_traza_ejecucion    NUMBER(12) := NULL;
        v_nivel_detalle_traza   VARCHAR2(30) := 'COMPLETO';
        v_grabar_payloads_traza NUMBER(1) := 1;
        v_fecha_inicio_traza    TIMESTAMP := SYSTIMESTAMP;
    BEGIN
        IF p_json_entrada IS NOT NULL AND DBMS_LOB.GETLENGTH(p_json_entrada) > 0 THEN
            v_obj_in := JSON_OBJECT_T.parse(p_json_entrada);
            
            IF v_obj_in.has('id_usuario_ejecutor') THEN
                v_id_usuario_ejecutor := v_obj_in.get_number('id_usuario_ejecutor');
            END IF;
            IF v_obj_in.has('codigo_traza') THEN
                v_codigo_traza := v_obj_in.get_string('codigo_traza');
            END IF;
            IF v_obj_in.has('id_especialidad') THEN
                v_id_especialidad := v_obj_in.get_number('id_especialidad');
            END IF;
            IF v_obj_in.has('id_convenio') THEN
                v_id_convenio := v_obj_in.get_number('id_convenio');
            END IF;
            IF v_obj_in.has('id_tipo_aseguramiento') THEN
                v_id_tipo_aseguramiento := v_obj_in.get_number('id_tipo_aseguramiento');
            END IF;
            IF v_obj_in.has('modalidad') THEN
                v_modalidad := v_obj_in.get_string('modalidad');
            END IF;
            IF v_obj_in.has('busqueda') THEN
                v_busqueda := v_obj_in.get_string('busqueda');
            END IF;
            IF v_obj_in.has('pagina') THEN
                v_pagina := NVL(v_obj_in.get_number('pagina'), 1);
            END IF;
            IF v_obj_in.has('registros_pagina') THEN
                v_registros_pagina := NVL(v_obj_in.get_number('registros_pagina'), 12);
            END IF;
        END IF;

        IF v_codigo_traza IS NULL THEN
            v_codigo_traza := RAWTOHEX(SYS_GUID());
        END IF;
        v_ip_origen := SYS_CONTEXT('USERENV', 'IP_ADDRESS');

        -- Paso 1: Telemetría
        v_traza_activa := uti_manejo_trazas_pkg.f_debe_trazar(
            p_nombre_paquete => 'pkgln_directorio_profesionales',
            p_nombre_metodo  => 'p_consultar_directorio',
            p_id_usuario     => v_id_usuario_ejecutor,
            p_id_config_out  => v_id_config_traza,
            p_nivel_out      => v_nivel_detalle_traza,
            p_grabar_pay_out => v_grabar_payloads_traza
        );

        IF v_traza_activa THEN
            uti_manejo_trazas_pkg.p_iniciar_traza(
                p_nombre_paquete   => 'pkgln_directorio_profesionales',
                p_nombre_metodo    => 'p_consultar_directorio',
                p_id_config        => v_id_config_traza,
                p_id_usuario       => v_id_usuario_ejecutor,
                p_codigo_traza     => v_codigo_traza,
                p_ip_origen        => v_ip_origen,
                p_json_entrada     => p_json_entrada,
                p_grabar_payload   => v_grabar_payloads_traza,
                p_id_ejecucion_out => v_id_traza_ejecucion
            );
        END IF;

        -- Paso 2: Delegar al caso de negocio multi-tabla
        pkgcn_directorio_profesionales.p_consultar_profesionales_json(
            p_id_especialidad       => v_id_especialidad,
            p_id_convenio           => v_id_convenio,
            p_id_tipo_aseguramiento => v_id_tipo_aseguramiento,
            p_modalidad             => v_modalidad,
            p_busqueda              => v_busqueda,
            p_pagina                => v_pagina,
            p_registros_por_pagina  => v_registros_pagina,
            p_json_salida           => p_json_salida
        );

        -- Paso 3: Cierre exitoso de telemetría
        IF v_traza_activa AND v_id_traza_ejecucion IS NOT NULL THEN
            uti_manejo_trazas_pkg.p_finalizar_traza(
                p_id_ejecucion   => v_id_traza_ejecucion,
                p_fecha_inicio   => v_fecha_inicio_traza,
                p_json_salida    => p_json_salida,
                p_grabar_payload => v_grabar_payloads_traza
            );
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            IF v_traza_activa AND v_id_traza_ejecucion IS NOT NULL THEN
                uti_manejo_trazas_pkg.p_finalizar_traza_error(
                    p_id_ejecucion  => v_id_traza_ejecucion,
                    p_fecha_inicio  => v_fecha_inicio_traza,
                    p_codigo_error  => SQLCODE,
                    p_mensaje_error => SQLERRM
                );
            END IF;

            vro_error.tipo                := 'E';
            vro_error.nombre_programa     := 'PKGLN_DIRECTORIO_PROFESIONALES';
            vro_error.nombre_metodo       := 'p_consultar_directorio';
            vro_error.parametros          := p_json_entrada;
            vro_error.codigo_error        := TO_CHAR(SQLCODE);
            vro_error.texto_error         := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
            vro_error.mensaje_error       := SUBSTR(SQLERRM, 1, 4000);
            vro_error.fecha               := CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE);
            vro_error.usuario             := NVL(TO_CHAR(v_id_usuario_ejecutor), USER);
            vro_error.id_usuario_creacion := v_id_usuario_ejecutor;

            uti_ge_excepciones_pkg.p_grabar_log(vro_error);

            DECLARE
                v_res_err JSON_OBJECT_T := JSON_OBJECT_T();
            BEGIN
                v_res_err.put('codigo', -20000);
                v_res_err.put('error', -20000);
                v_res_err.put('mensaje', 'Error al consultar directorio: ' || vro_error.mensaje_error);
                p_json_salida := v_res_err.to_clob();
            END;
    END p_consultar_directorio;

    -- 2. Consultar disponibilidad y slots de un profesional (por día o semana)
    PROCEDURE p_consultar_disponibilidad (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_obj_in                JSON_OBJECT_T;
        v_id_usuario            NUMBER(12);
        v_id_usuario_ejecutor   NUMBER(12);
        v_fecha_str             VARCHAR2(30);
        v_fecha                 DATE;
        v_tipo_vista            VARCHAR2(20) := 'DIA';
        v_id_convenio           NUMBER(12);
        v_id_tipo_aseguramiento NUMBER(12) := 1;
        v_modalidad             VARCHAR2(10) := 'V';
        v_codigo_traza          VARCHAR2(100);
    BEGIN
        IF p_json_entrada IS NULL OR DBMS_LOB.GETLENGTH(p_json_entrada) = 0 THEN
            DECLARE
                v_res_err JSON_OBJECT_T := JSON_OBJECT_T();
            BEGIN
                v_res_err.put('codigo', -20001);
                v_res_err.put('error', -20001);
                v_res_err.put('mensaje', 'Payload requerido');
                p_json_salida := v_res_err.to_clob();
            END;
            RETURN;
        END IF;

        v_obj_in := JSON_OBJECT_T.parse(p_json_entrada);
        v_id_usuario := v_obj_in.get_number('id_usuario');
        IF v_id_usuario IS NULL THEN
            DECLARE
                v_res_err JSON_OBJECT_T := JSON_OBJECT_T();
            BEGIN
                v_res_err.put('codigo', -20002);
                v_res_err.put('error', -20002);
                v_res_err.put('mensaje', 'El id_usuario del profesional es obligatorio');
                p_json_salida := v_res_err.to_clob();
            END;
            RETURN;
        END IF;

        IF v_obj_in.has('id_usuario_ejecutor') THEN
            v_id_usuario_ejecutor := v_obj_in.get_number('id_usuario_ejecutor');
        END IF;

        IF v_obj_in.has('fecha') THEN
            v_fecha_str := v_obj_in.get_string('fecha');
        END IF;

        BEGIN
            v_fecha := TO_DATE(TRIM(v_fecha_str), 'YYYY-MM-DD');
        EXCEPTION
            WHEN OTHERS THEN
                v_fecha := TRUNC(SYSDATE);
        END;

        IF v_obj_in.has('tipo_vista') THEN
            v_tipo_vista := UPPER(TRIM(v_obj_in.get_string('tipo_vista')));
        END IF;
        IF v_obj_in.has('id_convenio') THEN
            v_id_convenio := v_obj_in.get_number('id_convenio');
        END IF;
        IF v_obj_in.has('id_tipo_aseguramiento') THEN
            v_id_tipo_aseguramiento := v_obj_in.get_number('id_tipo_aseguramiento');
        END IF;
        IF v_obj_in.has('modalidad') THEN
            v_modalidad := v_obj_in.get_string('modalidad');
        END IF;

        IF v_tipo_vista = 'SEMANA' THEN
            pkgcn_directorio_profesionales.p_consultar_slots_semana_json(
                p_id_usuario            => v_id_usuario,
                p_fecha_inicio          => v_fecha,
                p_id_convenio           => v_id_convenio,
                p_id_tipo_aseguramiento => v_id_tipo_aseguramiento,
                p_modalidad             => v_modalidad,
                p_json_salida           => p_json_salida
            );
        ELSE
            pkgcn_directorio_profesionales.p_consultar_slots_dia_json(
                p_id_usuario            => v_id_usuario,
                p_fecha                 => v_fecha,
                p_id_convenio           => v_id_convenio,
                p_id_tipo_aseguramiento => v_id_tipo_aseguramiento,
                p_modalidad             => v_modalidad,
                p_json_salida           => p_json_salida
            );
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            vro_error.tipo                := 'E';
            vro_error.nombre_programa     := 'PKGLN_DIRECTORIO_PROFESIONALES';
            vro_error.nombre_metodo       := 'p_consultar_disponibilidad';
            vro_error.parametros          := p_json_entrada;
            vro_error.codigo_error        := TO_CHAR(SQLCODE);
            vro_error.texto_error         := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
            vro_error.mensaje_error       := SUBSTR(SQLERRM, 1, 4000);
            vro_error.fecha               := CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE);
            vro_error.usuario             := NVL(TO_CHAR(v_id_usuario_ejecutor), USER);
            vro_error.id_usuario_creacion := v_id_usuario_ejecutor;

            uti_ge_excepciones_pkg.p_grabar_log(vro_error);

            DECLARE
                v_res_err JSON_OBJECT_T := JSON_OBJECT_T();
            BEGIN
                v_res_err.put('codigo', -20000);
                v_res_err.put('error', -20000);
                v_res_err.put('mensaje', 'Error al consultar disponibilidad: ' || vro_error.mensaje_error);
                p_json_salida := v_res_err.to_clob();
            END;
    END p_consultar_disponibilidad;

    -- 3. Consultar catálogos maestros para los filtros del directorio
    PROCEDURE p_consultar_filtros (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
    BEGIN
        pkgcn_directorio_profesionales.p_consultar_filtros_catalogo_json(p_json_salida);
    EXCEPTION
        WHEN OTHERS THEN
            vro_error.tipo                := 'E';
            vro_error.nombre_programa     := 'PKGLN_DIRECTORIO_PROFESIONALES';
            vro_error.nombre_metodo       := 'p_consultar_filtros';
            vro_error.parametros          := p_json_entrada;
            vro_error.codigo_error        := TO_CHAR(SQLCODE);
            vro_error.texto_error         := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
            vro_error.mensaje_error       := SUBSTR(SQLERRM, 1, 4000);
            vro_error.fecha               := CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE);
            vro_error.usuario             := USER;

            uti_ge_excepciones_pkg.p_grabar_log(vro_error);

            DECLARE
                v_res_err JSON_OBJECT_T := JSON_OBJECT_T();
            BEGIN
                v_res_err.put('codigo', -20000);
                v_res_err.put('error', -20000);
                v_res_err.put('mensaje', 'Error al consultar filtros: ' || vro_error.mensaje_error);
                p_json_salida := v_res_err.to_clob();
            END;
    END p_consultar_filtros;

    -- 4. Orquestar la actualización de slots de cita (Marcar/Desmarcar) en el bitmap
    --    Calcula automáticamente duracion_minutos si no se proporciona, a partir de
    --    id_profesional, tipo de aseguramiento y modalidad.
    PROCEDURE p_actualizar_slots_cita (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_id_usuario            NUMBER;
        v_fecha_hora_str        VARCHAR2(50);
        v_fecha_hora            DATE;
        v_fecha_dia_str         VARCHAR2(10);
        v_duracion_min          NUMBER;
        v_tipo_operacion        VARCHAR2(2);
        v_id_convenio           NUMBER;
        v_id_tipo_aseguramiento NUMBER;
        v_modalidad             VARCHAR2(5);

        v_min_inicio            NUMBER;
        v_min_fin               NUMBER;
        v_idx_inicio            NUMBER;
        v_idx_fin               NUMBER;
        v_caracter_bit          VARCHAR2(1);
        v_filas_afectadas       NUMBER := 0;

        v_json_ca               CLOB;

        -- Telemetría
        v_traza_activa          BOOLEAN := FALSE;
        v_id_config_traza       NUMBER(12) := NULL;
        v_id_traza_ejecucion    NUMBER(12) := NULL;
        v_nivel_detalle_traza   VARCHAR2(30) := 'COMPLETO';
        v_grabar_payloads_traza NUMBER(1) := 1;
        v_codigo_traza          VARCHAR2(100);
        v_ip_origen             VARCHAR2(50) := 'LOCAL';
        v_id_usuario_ejecutor   NUMBER(12) := NULL;
        v_fecha_inicio_traza    TIMESTAMP := SYSTIMESTAMP;

        v_res_json              JSON_OBJECT_T;
    BEGIN
        IF p_json_entrada IS NULL THEN
            v_res_json := JSON_OBJECT_T();
            v_res_json.put('codigo', -20001);
            v_res_json.put('error', -20001);
            v_res_json.put('mensaje', 'Payload JSON de entrada es obligatorio');
            p_json_salida := v_res_json.to_clob();
            RETURN;
        END IF;

        -- Extraer parámetros con JSON_VALUE (admite id_profesional o id_usuario)
        v_id_usuario            := NVL(TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_profesional')),
                                       TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_usuario')));
        v_fecha_hora_str        := TRIM(JSON_VALUE(p_json_entrada, '$.fecha_hora'));
        v_tipo_operacion        := UPPER(TRIM(NVL(JSON_VALUE(p_json_entrada, '$.tipo_operacion'), 'M')));
        v_id_convenio           := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio'));
        v_id_tipo_aseguramiento := NVL(TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento')), 1);
        v_modalidad             := UPPER(TRIM(NVL(JSON_VALUE(p_json_entrada, '$.modalidad'),
                                                  NVL(JSON_VALUE(p_json_entrada, '$.clase_atencion'), 'V'))));
        v_duracion_min          := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.duracion_minutos'));
        v_codigo_traza          := NVL(JSON_VALUE(p_json_entrada, '$.codigo_traza'), SYS_GUID());
        v_id_usuario_ejecutor   := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_usuario_ejecutor'));

        -- Evaluación de telemetría institucional
        v_traza_activa := uti_manejo_trazas_pkg.f_debe_trazar(
            p_nombre_paquete   => 'PKGLN_DIRECTORIO_PROFESIONALES',
            p_nombre_metodo    => 'p_actualizar_slots_cita',
            p_id_usuario       => v_id_usuario_ejecutor,
            p_id_config_out    => v_id_config_traza,
            p_nivel_out        => v_nivel_detalle_traza,
            p_grabar_pay_out   => v_grabar_payloads_traza
        );

        IF v_traza_activa THEN
            uti_manejo_trazas_pkg.p_iniciar_traza(
                p_nombre_paquete   => 'PKGLN_DIRECTORIO_PROFESIONALES',
                p_nombre_metodo    => 'p_actualizar_slots_cita',
                p_id_config        => v_id_config_traza,
                p_id_usuario       => v_id_usuario_ejecutor,
                p_codigo_traza     => v_codigo_traza,
                p_ip_origen        => v_ip_origen,
                p_json_entrada     => CASE WHEN v_grabar_payloads_traza = 1 THEN p_json_entrada ELSE NULL END,
                p_grabar_payload   => v_grabar_payloads_traza,
                p_id_ejecucion_out => v_id_traza_ejecucion
            );
        END IF;

        -- Validaciones de negocio
        IF v_id_usuario IS NULL OR v_fecha_hora_str IS NULL THEN
            v_res_json := JSON_OBJECT_T();
            v_res_json.put('codigo', -20002);
            v_res_json.put('error', -20002);
            v_res_json.put('mensaje', 'Los campos id_profesional/id_usuario y fecha_hora son obligatorios');
            p_json_salida := v_res_json.to_clob();
            RETURN;
        END IF;

        IF v_tipo_operacion NOT IN ('M', 'D') THEN
            v_res_json := JSON_OBJECT_T();
            v_res_json.put('codigo', -20003);
            v_res_json.put('error', -20003);
            v_res_json.put('mensaje', 'tipo_operacion invalido. Debe ser M (Marcar) o D (Desmarcar)');
            p_json_salida := v_res_json.to_clob();
            RETURN;
        END IF;

        -- Regla: Si no se pasa duracion_minutos, se calcula automáticamente según id_profesional, aseguramiento y modalidad
        IF v_duracion_min IS NULL OR v_duracion_min <= 0 THEN
            DECLARE
                v_obj_tiempo JSON_OBJECT_T := JSON_OBJECT_T();
            BEGIN
                v_obj_tiempo.put('id_usuario', v_id_usuario);
                v_obj_tiempo.put('id_tipo_aseguramiento', v_id_tipo_aseguramiento);
                v_obj_tiempo.put('modalidad', v_modalidad);
                v_duracion_min := pkgca_tkr_tiempos_atencion.f_obtener_duracion_cita(v_obj_tiempo.to_clob());
            END;

            IF v_duracion_min IS NULL OR v_duracion_min <= 0 THEN
                v_duracion_min := 20; -- Fallback por defecto
            END IF;
        END IF;

        -- Parsear fecha y hora
        DECLARE
            v_err_fecha VARCHAR2(1000);
        BEGIN
            IF INSTR(v_fecha_hora_str, 'T') > 0 THEN
                v_fecha_hora := TO_DATE(SUBSTR(v_fecha_hora_str, 1, 19), 'YYYY-MM-DD"T"HH24:MI:SS');
            ELSIF LENGTH(v_fecha_hora_str) >= 16 THEN
                v_fecha_hora := TO_DATE(SUBSTR(v_fecha_hora_str, 1, 16), 'YYYY-MM-DD HH24:MI');
            ELSE
                v_res_json := JSON_OBJECT_T();
                v_res_json.put('codigo', -20004);
                v_res_json.put('error', -20004);
                v_res_json.put('mensaje', 'Formato de fecha_hora invalido. Use YYYY-MM-DD HH24:MI');
                p_json_salida := v_res_json.to_clob();
                RETURN;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                v_err_fecha := SUBSTR(SQLERRM, 1, 1000);
                v_res_json := JSON_OBJECT_T();
                v_res_json.put('codigo', -20004);
                v_res_json.put('error', -20004);
                v_res_json.put('mensaje', 'Error al interpretar fecha_hora: ' || v_err_fecha);
                p_json_salida := v_res_json.to_clob();
                RETURN;
        END;

        v_fecha_dia_str := TO_CHAR(v_fecha_hora, 'YYYY-MM-DD');
        v_min_inicio    := TO_NUMBER(TO_CHAR(v_fecha_hora, 'HH24')) * 60 + TO_NUMBER(TO_CHAR(v_fecha_hora, 'MI'));
        v_min_fin       := v_min_inicio + v_duracion_min;

        -- Cálculo de posiciones en el vector de 288 bits
        v_idx_inicio := TRUNC(v_min_inicio / 5) + 1;
        v_idx_fin    := TRUNC(v_min_fin / 5);

        IF v_idx_inicio < 1 THEN v_idx_inicio := 1; END IF;
        IF v_idx_fin > 288 THEN v_idx_fin := 288; END IF;

        IF v_tipo_operacion = 'M' THEN
            v_caracter_bit := '1';
        ELSE
            v_caracter_bit := '0';
        END IF;

        -- Construir payload JSON para la capa DML mono-tabla pkgca_ usando JSON_OBJECT_T en memoria
        DECLARE
            v_obj_ca JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
            v_obj_ca.put('id_usuario', v_id_usuario);
            v_obj_ca.put('fecha', v_fecha_dia_str);
            v_obj_ca.put('idx_inicio', v_idx_inicio);
            v_obj_ca.put('idx_fin', v_idx_fin);
            v_obj_ca.put('caracter_bit', v_caracter_bit);
            v_obj_ca.put('id_convenio', v_id_convenio);
            v_obj_ca.put('id_tipo_aseguramiento', v_id_tipo_aseguramiento);
            v_obj_ca.put('modalidad', v_modalidad);
            v_json_ca := v_obj_ca.to_clob();
        END;

        -- Invocar la capa de acceso y DML mono-tabla
        pkgca_tkr_disponibilidad_bitmap.p_actualizar_bitmap_ocupado(
            p_json_entrada    => v_json_ca,
            p_filas_afectadas => v_filas_afectadas
        );

        -- Confirmación controlada de la transacción (p_do_commit)
        p_do_commit('pkgln_directorio_profesionales.p_actualizar_slots_cita');

        -- Finalizar telemetría exitosa
        IF v_traza_activa AND v_id_traza_ejecucion IS NOT NULL THEN
            uti_manejo_trazas_pkg.p_finalizar_traza(
                p_id_ejecucion   => v_id_traza_ejecucion,
                p_fecha_inicio   => v_fecha_inicio_traza,
                p_json_salida    => '{"codigo": 0, "filas_afectadas": ' || v_filas_afectadas || '}',
                p_grabar_payload => v_grabar_payloads_traza
            );
        END IF;

        -- Salida exitosa construida en memoria con JSON_OBJECT_T
        v_res_json := JSON_OBJECT_T();
        v_res_json.put('codigo', 0);
        v_res_json.put('mensaje', CASE 
                                     WHEN v_tipo_operacion = 'M' THEN 'Slots de cita reservados/marcados exitosamente'
                                     ELSE 'Slots de cita liberados/desmarcados exitosamente'
                                 END);
        v_res_json.put('id_profesional', v_id_usuario);
        v_res_json.put('id_usuario', v_id_usuario);
        v_res_json.put('fecha', v_fecha_dia_str);
        v_res_json.put('hora_inicio', TO_CHAR(v_fecha_hora, 'HH24:MI'));
        v_res_json.put('duracion_minutos', v_duracion_min);
        v_res_json.put('idx_inicio', v_idx_inicio);
        v_res_json.put('idx_fin', v_idx_fin);
        v_res_json.put('tipo_operacion', v_tipo_operacion);
        v_res_json.put('filas_afectadas', v_filas_afectadas);
        p_json_salida := v_res_json.to_clob();

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;

            vro_error.tipo                := 'E';
            vro_error.nombre_programa     := 'PKGLN_DIRECTORIO_PROFESIONALES';
            vro_error.nombre_metodo       := 'p_actualizar_slots_cita';
            vro_error.parametros          := p_json_entrada;
            vro_error.codigo_error        := TO_CHAR(SQLCODE);
            vro_error.texto_error         := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
            vro_error.mensaje_error       := SUBSTR(SQLERRM, 1, 4000);
            vro_error.fecha               := CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE);
            vro_error.usuario             := NVL(TO_CHAR(v_id_usuario_ejecutor), USER);
            vro_error.id_usuario_creacion := v_id_usuario_ejecutor;

            uti_ge_excepciones_pkg.p_grabar_log(vro_error);

            IF v_traza_activa AND v_id_traza_ejecucion IS NOT NULL THEN
                uti_manejo_trazas_pkg.p_finalizar_traza_error(
                    p_id_ejecucion  => v_id_traza_ejecucion,
                    p_fecha_inicio  => v_fecha_inicio_traza,
                    p_codigo_error  => SQLCODE,
                    p_mensaje_error => SQLERRM
                );
            END IF;

            v_res_json := JSON_OBJECT_T();
            v_res_json.put('codigo', -20000);
            v_res_json.put('error', -20000);
            v_res_json.put('mensaje', 'Error al actualizar slots de cita: ' || vro_error.mensaje_error);
            p_json_salida := v_res_json.to_clob();
    END p_actualizar_slots_cita;

    -- 5. Marcar o desmarcar un rango explícito de slots pasando id_usuario, fecha_hora y duracion_minutos
    PROCEDURE p_marcar_desmarcar_slots (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_id_usuario            NUMBER;
        v_fecha_hora_str        VARCHAR2(50);
        v_fecha_hora            DATE;
        v_fecha_dia_str         VARCHAR2(10);
        v_duracion_min          NUMBER;
        v_tipo_operacion        VARCHAR2(2);
        v_id_convenio           NUMBER;
        v_id_tipo_aseguramiento NUMBER;
        v_modalidad             VARCHAR2(5);

        v_min_inicio            NUMBER;
        v_min_fin               NUMBER;
        v_idx_inicio            NUMBER;
        v_idx_fin               NUMBER;
        v_caracter_bit          VARCHAR2(1);
        v_filas_afectadas       NUMBER := 0;

        v_json_ca               CLOB;
        v_res_json              JSON_OBJECT_T;
    BEGIN
        IF p_json_entrada IS NULL THEN
            v_res_json := JSON_OBJECT_T();
            v_res_json.put('codigo', -20001);
            v_res_json.put('error', -20001);
            v_res_json.put('mensaje', 'Payload JSON de entrada es obligatorio');
            p_json_salida := v_res_json.to_clob();
            RETURN;
        END IF;

        -- Extraer parámetros obligatorios y opcionales
        v_id_usuario            := NVL(TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_profesional')),
                                       TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_usuario')));
        v_fecha_hora_str        := TRIM(JSON_VALUE(p_json_entrada, '$.fecha_hora'));
        v_duracion_min          := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.duracion_minutos'));
        
        -- Detección flexible de tipo_operacion ('M' para Marcar por defecto, 'D' para Desmarcar/Liberar)
        v_tipo_operacion        := UPPER(TRIM(NVL(JSON_VALUE(p_json_entrada, '$.tipo_operacion'),
                                              NVL(JSON_VALUE(p_json_entrada, '$.operacion'),
                                              NVL(JSON_VALUE(p_json_entrada, '$.accion'), 'M')))));
        IF v_tipo_operacion IN ('DESMARCAR', 'LIBERAR', 'CANCELAR', 'D', '0') THEN
            v_tipo_operacion := 'D';
        ELSE
            v_tipo_operacion := 'M';
        END IF;

        v_id_convenio           := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio'));
        v_id_tipo_aseguramiento := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento'));
        v_modalidad             := UPPER(TRIM(NVL(JSON_VALUE(p_json_entrada, '$.modalidad'),
                                                  JSON_VALUE(p_json_entrada, '$.clase_atencion'))));

        IF v_id_usuario IS NULL OR v_fecha_hora_str IS NULL OR v_duracion_min IS NULL OR v_duracion_min <= 0 THEN
            v_res_json := JSON_OBJECT_T();
            v_res_json.put('codigo', -20002);
            v_res_json.put('error', -20002);
            v_res_json.put('mensaje', 'Los parametros id_usuario, fecha_hora y duracion_minutos son obligatorios');
            p_json_salida := v_res_json.to_clob();
            RETURN;
        END IF;

        -- Parsear fecha y hora
        BEGIN
            IF INSTR(v_fecha_hora_str, 'T') > 0 THEN
                v_fecha_hora := TO_DATE(SUBSTR(v_fecha_hora_str, 1, 19), 'YYYY-MM-DD"T"HH24:MI:SS');
            ELSIF LENGTH(v_fecha_hora_str) >= 16 THEN
                v_fecha_hora := TO_DATE(SUBSTR(v_fecha_hora_str, 1, 16), 'YYYY-MM-DD HH24:MI');
            ELSE
                v_res_json := JSON_OBJECT_T();
                v_res_json.put('codigo', -20004);
                v_res_json.put('error', -20004);
                v_res_json.put('mensaje', 'Formato de fecha_hora invalido. Use YYYY-MM-DD HH24:MI');
                p_json_salida := v_res_json.to_clob();
                RETURN;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                v_res_json := JSON_OBJECT_T();
                v_res_json.put('codigo', -20004);
                v_res_json.put('error', -20004);
                v_res_json.put('mensaje', 'Error al interpretar fecha_hora: ' || SUBSTR(SQLERRM, 1, 500));
                p_json_salida := v_res_json.to_clob();
                RETURN;
        END;

        v_fecha_dia_str := TO_CHAR(v_fecha_hora, 'YYYY-MM-DD');
        v_min_inicio    := TO_NUMBER(TO_CHAR(v_fecha_hora, 'HH24')) * 60 + TO_NUMBER(TO_CHAR(v_fecha_hora, 'MI'));
        v_min_fin       := v_min_inicio + v_duracion_min;

        -- Índices en el vector de 288 posiciones
        v_idx_inicio := TRUNC(v_min_inicio / 5) + 1;
        v_idx_fin    := TRUNC(v_min_fin / 5);

        IF v_idx_inicio < 1 THEN v_idx_inicio := 1; END IF;
        IF v_idx_fin > 288 THEN v_idx_fin := 288; END IF;

        IF v_tipo_operacion = 'M' THEN
            v_caracter_bit := '1';
        ELSE
            v_caracter_bit := '0';
        END IF;

        -- Construir payload JSON para la capa DML pkgca_ usando JSON_OBJECT_T en memoria
        DECLARE
            v_obj_ca JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
            v_obj_ca.put('id_usuario', v_id_usuario);
            v_obj_ca.put('fecha', v_fecha_dia_str);
            v_obj_ca.put('idx_inicio', v_idx_inicio);
            v_obj_ca.put('idx_fin', v_idx_fin);
            v_obj_ca.put('caracter_bit', v_caracter_bit);
            IF v_id_convenio IS NOT NULL THEN
                v_obj_ca.put('id_convenio', v_id_convenio);
            END IF;
            IF v_id_tipo_aseguramiento IS NOT NULL THEN
                v_obj_ca.put('id_tipo_aseguramiento', v_id_tipo_aseguramiento);
            END IF;
            IF v_modalidad IS NOT NULL THEN
                v_obj_ca.put('modalidad', v_modalidad);
            END IF;
            v_json_ca := v_obj_ca.to_clob();
        END;

        -- Invocar la capa DML mono-tabla
        pkgca_tkr_disponibilidad_bitmap.p_actualizar_bitmap_ocupado(
            p_json_entrada    => v_json_ca,
            p_filas_afectadas => v_filas_afectadas
        );

        -- Confirmación controlada
        p_do_commit('pkgln_directorio_profesionales.p_marcar_desmarcar_slots');

        -- Salida exitosa estructurada con JSON_OBJECT_T
        v_res_json := JSON_OBJECT_T();
        v_res_json.put('codigo', 0);
        v_res_json.put('mensaje', CASE 
                                     WHEN v_tipo_operacion = 'M' THEN 'Slots reservados/marcados exitosamente'
                                     ELSE 'Slots liberados/desmarcados exitosamente'
                                 END);
        v_res_json.put('id_profesional', v_id_usuario);
        v_res_json.put('id_usuario', v_id_usuario);
        v_res_json.put('fecha', v_fecha_dia_str);
        v_res_json.put('hora_inicio', TO_CHAR(v_fecha_hora, 'HH24:MI'));
        v_res_json.put('duracion_minutos', v_duracion_min);
        v_res_json.put('idx_inicio', v_idx_inicio);
        v_res_json.put('idx_fin', v_idx_fin);
        v_res_json.put('tipo_operacion', v_tipo_operacion);
        v_res_json.put('filas_afectadas', v_filas_afectadas);
        p_json_salida := v_res_json.to_clob();

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;

            vro_error.tipo                := 'E';
            vro_error.nombre_programa     := 'PKGLN_DIRECTORIO_PROFESIONALES';
            vro_error.nombre_metodo       := 'p_marcar_desmarcar_slots';
            vro_error.parametros          := p_json_entrada;
            vro_error.codigo_error        := TO_CHAR(SQLCODE);
            vro_error.texto_error         := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
            vro_error.mensaje_error       := SUBSTR(SQLERRM, 1, 4000);
            vro_error.fecha               := CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE);
            vro_error.usuario             := USER;
            vro_error.id_usuario_creacion := NULL;

            uti_ge_excepciones_pkg.p_grabar_log(vro_error);

            v_res_json := JSON_OBJECT_T();
            v_res_json.put('codigo', -20000);
            v_res_json.put('error', -20000);
            v_res_json.put('mensaje', 'Error al marcar/desmarcar slots: ' || vro_error.mensaje_error);
            p_json_salida := v_res_json.to_clob();
    END p_marcar_desmarcar_slots;

END pkgln_directorio_profesionales;
/
