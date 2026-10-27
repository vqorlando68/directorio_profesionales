CREATE OR REPLACE PACKAGE BODY pkgln_directorio_profesionales AS
    /*
    || =========================================================================
    || Paquete: pkgln_directorio_profesionales (Body)
    || Propósito: Orquestador transaccional con gobierno de lógica de dominio,
    ||            motor de disponibilidad y slots, telemetría y excepciones.
    || Estándar: oracle-plsql-architecture
    || =========================================================================
    */

    vro_error tkr_errores%ROWTYPE;

    -- =========================================================================
    -- FUNCIONES Y PROCEDIMIENTOS AUXILIARES DE LÓGICA DE NEGOCIO (PRIVADOS)
    -- =========================================================================

    -- Conversión de hora HH24:MI a minutos del día (0..1439)
    FUNCTION f_hora_a_minutos (p_hora IN VARCHAR2) RETURN NUMBER IS
        v_h NUMBER;
        v_m NUMBER;
    BEGIN
        IF p_hora IS NULL OR INSTR(p_hora, ':') = 0 THEN
            RETURN 0;
        END IF;
        v_h := TO_NUMBER(SUBSTR(p_hora, 1, INSTR(p_hora, ':') - 1));
        v_m := TO_NUMBER(SUBSTR(p_hora, INSTR(p_hora, ':') + 1));
        RETURN (v_h * 60) + v_m;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END f_hora_a_minutos;

    -- Conversión de minutos del día a hora HH24:MI
    FUNCTION f_minutos_a_hora (p_minutos IN NUMBER) RETURN VARCHAR2 IS
        v_h NUMBER;
        v_m NUMBER;
    BEGIN
        v_h := TRUNC(p_minutos / 60);
        v_m := MOD(p_minutos, 60);
        RETURN LPAD(TO_CHAR(v_h), 2, '0') || ':' || LPAD(TO_CHAR(v_m), 2, '0');
    END f_minutos_a_hora;

    -- Obtener código de día canónico TEKER ('LU', 'MA', 'MI', 'JU', 'VI', 'SA', 'DO')
    FUNCTION f_obtener_dia_semana (p_fecha IN DATE) RETURN VARCHAR2 IS
        v_dias VARCHAR2(30);
    BEGIN
        v_dias := TO_CHAR(p_fecha, 'DY', 'NLS_DATE_LANGUAGE=SPANISH');
        v_dias := UPPER(SUBSTR(TRIM(v_dias), 1, 2));
        CASE v_dias
            WHEN 'LU' THEN RETURN 'LU';
            WHEN 'MA' THEN RETURN 'MA';
            WHEN 'MI' THEN RETURN 'MI';
            WHEN 'JU' THEN RETURN 'JU';
            WHEN 'VI' THEN RETURN 'VI';
            WHEN 'SÁ' THEN RETURN 'SA';
            WHEN 'SA' THEN RETURN 'SA';
            WHEN 'DO' THEN RETURN 'DO';
            ELSE
                RETURN CASE TO_CHAR(p_fecha, 'D')
                    WHEN '1' THEN 'DO'
                    WHEN '2' THEN 'LU'
                    WHEN '3' THEN 'MA'
                    WHEN '4' THEN 'MI'
                    WHEN '5' THEN 'JU'
                    WHEN '6' THEN 'VI'
                    WHEN '7' THEN 'SA'
                    ELSE 'LU'
                END;
        END CASE;
    END f_obtener_dia_semana;

    -- Motor privado de cálculo de disponibilidad para un día específico
    PROCEDURE p_calcular_disponibilidad_dia (
        p_id_usuario            IN  NUMBER,
        p_fecha                 IN  DATE,
        p_id_convenio           IN  NUMBER   DEFAULT NULL,
        p_id_tipo_aseguramiento IN  NUMBER   DEFAULT 1,
        p_modalidad             IN  VARCHAR2 DEFAULT 'V',
        p_json_salida           OUT CLOB
    ) IS
        v_dia_semana          VARCHAR2(10);
        v_trabaja_festivos    VARCHAR2(1) := 'N';
        v_es_festivo          BOOLEAN := FALSE;
        v_es_domingo          BOOLEAN := FALSE;
        v_bloqueado_ausencia   BOOLEAN := FALSE;
        v_tipo_horario_aplica VARCHAR2(30) := 'NINGUNO';
        v_duracion_min        NUMBER := 20;
        v_bitmap              VARCHAR2(288) := RPAD('0', 288, '0');
        v_slots_arr           JSON_ARRAY_T := JSON_ARRAY_T();
        v_slot_obj            JSON_OBJECT_T;
        v_total_slots         NUMBER := 0;

        TYPE t_turno_rec IS RECORD (
            id                     NUMBER,
            hora_desde             VARCHAR2(10),
            hora_hasta             VARCHAR2(10),
            id_convenio            NUMBER,
            id_tipo_aseguramiento  NUMBER,
            fecha_inicial          DATE,
            fecha_final            DATE,
            tipo_vigencia          VARCHAR2(30)
        );
        TYPE t_turnos_tab IS TABLE OF t_turno_rec INDEX BY PLS_INTEGER;
        v_turnos_todos t_turnos_tab;
        v_turnos_aplicar t_turnos_tab;
        v_cur_turnos   SYS_REFCURSOR;
        v_rec_id       NUMBER;
        v_rec_h_desde  VARCHAR2(10);
        v_rec_h_hasta  VARCHAR2(10);
        v_rec_conv     NUMBER;
        v_rec_aseg     NUMBER;
        v_rec_f_ini    DATE;
        v_rec_f_fin    DATE;
        v_idx_t        PLS_INTEGER := 0;

        v_tiene_por_dia       BOOLEAN := FALSE;
        v_tiene_personalizado BOOLEAN := FALSE;
        v_tiene_base          BOOLEAN := FALSE;
    BEGIN
        v_dia_semana := f_obtener_dia_semana(p_fecha);
        v_es_domingo := (v_dia_semana = 'DO');
        v_es_festivo := pkgca_tkr_festivos.f_es_festivo(p_fecha, 1);
        v_trabaja_festivos := pkgca_tkr_usuarios.f_trabaja_festivos(p_id_usuario);
        v_bloqueado_ausencia := pkgca_tkr_ausencias_profesional.f_existe_ausencia(p_id_usuario, p_fecha, p_fecha);

        -- Regla 1: Obtener duración según tipo de aseguramiento y modalidad
        DECLARE
            v_json_tiempo CLOB;
        BEGIN
            SELECT JSON_OBJECT(
                       'id_usuario'            VALUE p_id_usuario,
                       'id_tipo_aseguramiento' VALUE p_id_tipo_aseguramiento,
                       'modalidad'             VALUE p_modalidad
                       RETURNING CLOB
                   )
              INTO v_json_tiempo
              FROM DUAL;

            v_duracion_min := pkgca_tkr_tiempos_atencion.f_obtener_duracion_cita(v_json_tiempo);
        END;

        -- Regla 2: Bloqueo por ausencia médica programada
        IF v_bloqueado_ausencia THEN
            SELECT JSON_OBJECT(
                       'codigo'            VALUE 0,
                       'mensaje'           VALUE 'Día no disponible por ausencia programada del profesional',
                       'fecha'             VALUE TO_CHAR(p_fecha, 'YYYY-MM-DD'),
                       'dia_semana'        VALUE v_dia_semana,
                       'disponible'        VALUE 0,
                       'motivo_bloqueo'    VALUE 'AUSENCIA_PROGRAMADA',
                       'slots'             VALUE JSON_ARRAY(),
                       'bitmap_disponible' VALUE v_bitmap
                       RETURNING CLOB
                   )
              INTO p_json_salida
              FROM DUAL;
            RETURN;
        END IF;

        -- Regla 3: Consultar turnos multi-tabla desde pkgcn_ y resolver jerarquía de vigencias
        DECLARE
            v_json_turnos_in CLOB;
        BEGIN
            SELECT JSON_OBJECT(
                       'id_usuario'            VALUE p_id_usuario,
                       'dia_semana'            VALUE v_dia_semana,
                       'id_convenio'           VALUE p_id_convenio,
                       'id_tipo_aseguramiento' VALUE p_id_tipo_aseguramiento
                       RETURNING CLOB
                   )
              INTO v_json_turnos_in
              FROM DUAL;

            v_cur_turnos := pkgcn_directorio_profesionales.f_consultar_turnos(
                p_json_entrada => v_json_turnos_in
            );
        END;

        LOOP
            FETCH v_cur_turnos INTO v_rec_id, v_rec_h_desde, v_rec_h_hasta, v_rec_conv, v_rec_aseg, v_rec_f_ini, v_rec_f_fin;
            EXIT WHEN v_cur_turnos%NOTFOUND;

            v_idx_t := v_idx_t + 1;
            v_turnos_todos(v_idx_t).id := v_rec_id;
            v_turnos_todos(v_idx_t).hora_desde := v_rec_h_desde;
            v_turnos_todos(v_idx_t).hora_hasta := v_rec_h_hasta;
            v_turnos_todos(v_idx_t).id_convenio := v_rec_conv;
            v_turnos_todos(v_idx_t).id_tipo_aseguramiento := v_rec_aseg;
            v_turnos_todos(v_idx_t).fecha_inicial := v_rec_f_ini;
            v_turnos_todos(v_idx_t).fecha_final := v_rec_f_fin;

            -- Clasificar nivel de vigencia
            IF TRUNC(v_rec_f_ini) = TRUNC(p_fecha) AND TRUNC(v_rec_f_fin) = TRUNC(p_fecha) THEN
                v_turnos_todos(v_idx_t).tipo_vigencia := 'POR_DIA';
                v_tiene_por_dia := TRUE;
            ELSIF TRUNC(v_rec_f_ini) <= TRUNC(p_fecha) AND TRUNC(v_rec_f_fin) >= TRUNC(p_fecha) AND TRUNC(v_rec_f_ini) <> TRUNC(v_rec_f_fin) THEN
                v_turnos_todos(v_idx_t).tipo_vigencia := 'PERSONALIZADO';
                v_tiene_personalizado := TRUE;
            ELSIF TRUNC(v_rec_f_ini) <= TRUNC(p_fecha) AND v_rec_f_fin IS NULL THEN
                v_turnos_todos(v_idx_t).tipo_vigencia := 'BASE';
                v_tiene_base := TRUE;
            ELSE
                v_turnos_todos(v_idx_t).tipo_vigencia := 'FUERA_RANGO';
            END IF;
        END LOOP;
        CLOSE v_cur_turnos;

        -- Jerarquía de vigencias: POR_DIA > PERSONALIZADO > BASE
        IF v_tiene_por_dia THEN
            v_tipo_horario_aplica := 'POR_DIA';
        ELSE
            IF (v_es_domingo OR v_es_festivo) AND v_trabaja_festivos = 'N' THEN
                SELECT JSON_OBJECT(
                           'codigo'            VALUE 0,
                           'mensaje'           VALUE 'Profesional no labora domingos ni festivos',
                           'fecha'             VALUE TO_CHAR(p_fecha, 'YYYY-MM-DD'),
                           'dia_semana'        VALUE v_dia_semana,
                           'disponible'        VALUE 0,
                           'motivo_bloqueo'    VALUE 'FESTIVO_NO_LABORAL',
                           'slots'             VALUE JSON_ARRAY(),
                           'bitmap_disponible' VALUE v_bitmap
                           RETURNING CLOB
                       )
                  INTO p_json_salida
                  FROM DUAL;
                RETURN;
            END IF;

            IF v_tiene_personalizado THEN
                v_tipo_horario_aplica := 'PERSONALIZADO';
            ELSIF v_tiene_base THEN
                v_tipo_horario_aplica := 'BASE';
            ELSE
                v_tipo_horario_aplica := 'NINGUNO';
            END IF;
        END IF;

        IF v_tipo_horario_aplica = 'NINGUNO' THEN
            SELECT JSON_OBJECT(
                       'codigo'            VALUE 0,
                       'mensaje'           VALUE 'Sin programación de horario para esta fecha',
                       'fecha'             VALUE TO_CHAR(p_fecha, 'YYYY-MM-DD'),
                       'dia_semana'        VALUE v_dia_semana,
                       'disponible'        VALUE 0,
                       'motivo_bloqueo'    VALUE 'SIN_HORARIO',
                       'slots'             VALUE JSON_ARRAY(),
                       'bitmap_disponible' VALUE v_bitmap
                       RETURNING CLOB
                   )
              INTO p_json_salida
              FROM DUAL;
            RETURN;
        END IF;

        -- Regla 4: Consultar vector de slots ocupados / citas reservadas
        DECLARE
            v_bitmap_ocupado_db VARCHAR2(288) := RPAD('0', 288, '0');
        BEGIN
            BEGIN
                SELECT b.bitmap_ocupado
                  INTO v_bitmap_ocupado_db
                  FROM tkr_disponibilidad_bitmap b
                 WHERE b.id_usuario = p_id_usuario
                   AND TRUNC(b.fecha) = TRUNC(p_fecha)
                   AND (p_id_convenio IS NULL OR b.id_convenio = p_id_convenio OR b.id_convenio IS NULL)
                   AND (p_id_tipo_aseguramiento IS NULL OR b.id_tipo_aseguramiento = p_id_tipo_aseguramiento)
                   AND (p_modalidad IS NULL OR b.modalidad = p_modalidad)
                   AND ROWNUM = 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_bitmap_ocupado_db := RPAD('0', 288, '0');
            END;

            -- Regla 5: Generar slots e intervalos de 5 min respetando los turnos seleccionados
            v_total_slots := 0;
            FOR i IN 1..v_turnos_todos.COUNT LOOP
                IF v_turnos_todos(i).tipo_vigencia = v_tipo_horario_aplica THEN
                    DECLARE
                        v_min_inicio NUMBER := f_hora_a_minutos(v_turnos_todos(i).hora_desde);
                        v_min_fin    NUMBER := f_hora_a_minutos(v_turnos_todos(i).hora_hasta);
                        v_actual     NUMBER := v_min_inicio;
                        v_slot_fin   NUMBER;
                        v_idx_inicio NUMBER;
                        v_idx_fin    NUMBER;
                        v_ocupado    BOOLEAN;
                    BEGIN
                        WHILE (v_actual + v_duracion_min) <= v_min_fin LOOP
                            v_slot_fin   := v_actual + v_duracion_min;
                            v_idx_inicio := TRUNC(v_actual / 5) + 1;
                            v_idx_fin    := TRUNC(v_slot_fin / 5);

                            -- Validar si algún bit del slot está ocupado ('1')
                            v_ocupado := FALSE;
                            FOR b_idx IN v_idx_inicio..v_idx_fin LOOP
                                IF b_idx BETWEEN 1 AND 288 THEN
                                    IF SUBSTR(v_bitmap_ocupado_db, b_idx, 1) = '1' THEN
                                        v_ocupado := TRUE;
                                        EXIT;
                                    END IF;
                                END IF;
                            END LOOP;

                            IF NOT v_ocupado THEN
                                v_slot_obj := JSON_OBJECT_T();
                                v_slot_obj.put('hora_inicio', f_minutos_a_hora(v_actual));
                                v_slot_obj.put('hora_fin', f_minutos_a_hora(v_slot_fin));
                                v_slot_obj.put('duracion_minutos', v_duracion_min);
                                v_slot_obj.put('id_horario', v_turnos_todos(i).id);
                                v_slot_obj.put('id_convenio', v_turnos_todos(i).id_convenio);
                                v_slot_obj.put('disponible', 1);
                                v_slots_arr.append(v_slot_obj);

                                FOR b_idx IN v_idx_inicio..v_idx_fin LOOP
                                    IF b_idx BETWEEN 1 AND 288 THEN
                                        v_bitmap := SUBSTR(v_bitmap, 1, b_idx - 1) || '1' || SUBSTR(v_bitmap, b_idx + 1);
                                    END IF;
                                END LOOP;

                                v_total_slots := v_total_slots + 1;
                            END IF;

                            v_actual := v_slot_fin;
                        END LOOP;
                    END;
                END IF;
            END LOOP;
        END;

        DECLARE
            v_res_obj JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
            v_res_obj.put('codigo', 0);
            v_res_obj.put('mensaje', 'Disponibilidad recuperada exitosamente');
            v_res_obj.put('id_usuario', p_id_usuario);
            v_res_obj.put('fecha', TO_CHAR(p_fecha, 'YYYY-MM-DD'));
            v_res_obj.put('dia_semana', v_dia_semana);
            v_res_obj.put('tipo_horario_aplica', v_tipo_horario_aplica);
            v_res_obj.put('duracion_cita_min', v_duracion_min);
            v_res_obj.put('total_slots', v_total_slots);
            v_res_obj.put('bitmap_disponible', v_bitmap);
            v_res_obj.put('slots', v_slots_arr);
            p_json_salida := v_res_obj.to_clob();
        END;
    END p_calcular_disponibilidad_dia;

    -- =========================================================================
    -- PROCEDIMIENTOS PÚBLICOS DEL ORQUESTADOR
    -- =========================================================================

    -- 1. Consultar directorio paginado de profesionales habilitados con filtros
    PROCEDURE p_consultar_directorio (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_obj_in                JSON_OBJECT_T;
        v_id_usuario_ejecutor   NUMBER(12);
        v_codigo_traza          VARCHAR2(100);
        v_ip_origen             VARCHAR2(50);
        
        v_id_especialidad       NUMBER(12);
        v_id_convenio           NUMBER(12);
        v_id_tipo_aseguramiento NUMBER(12);
        v_modalidad             VARCHAR2(10);
        v_busqueda              VARCHAR2(200);
        v_pagina                NUMBER := 1;
        v_registros_pagina      NUMBER := 12;

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

        -- Telemetría
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

        -- Delegar consulta relacional multi-tabla a pkgcn_
        pkgcn_directorio_profesionales.p_consultar_profesionales_json(
            p_json_entrada => p_json_entrada,
            p_json_salida  => p_json_salida
        );

        -- Cierre de telemetría
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

    -- 2. Consultar disponibilidad y slots de un profesional (por día, semana o rango)
    PROCEDURE p_consultar_disponibilidad (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_obj_in                JSON_OBJECT_T;
        v_id_usuario            NUMBER(12);
        v_id_usuario_ejecutor   NUMBER(12);
        v_fecha_str             VARCHAR2(30);
        v_fecha                 DATE;
        v_fecha_ini_str         VARCHAR2(30);
        v_fecha_fin_str         VARCHAR2(30);
        v_fecha_inicio          DATE;
        v_fecha_fin             DATE;
        v_tipo_vista            VARCHAR2(20) := 'DIA';
        v_id_convenio           NUMBER(12);
        v_id_tipo_aseguramiento NUMBER(12) := 1;
        v_modalidad             VARCHAR2(10) := 'V';
        v_codigo_traza          VARCHAR2(100);

        v_traza_activa          BOOLEAN := FALSE;
        v_id_config_traza       NUMBER(12) := NULL;
        v_id_traza_ejecucion    NUMBER(12) := NULL;
        v_nivel_detalle_traza   VARCHAR2(30) := 'COMPLETO';
        v_grabar_payloads_traza NUMBER(1) := 1;
        v_fecha_inicio_traza    TIMESTAMP := SYSTIMESTAMP;
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
        IF v_obj_in.has('codigo_traza') THEN
            v_codigo_traza := v_obj_in.get_string('codigo_traza');
        END IF;
        IF v_codigo_traza IS NULL THEN
            v_codigo_traza := RAWTOHEX(SYS_GUID());
        END IF;

        IF v_obj_in.has('fecha') THEN
            v_fecha_str := v_obj_in.get_string('fecha');
        END IF;
        IF v_obj_in.has('fecha_inicio') THEN
            v_fecha_ini_str := v_obj_in.get_string('fecha_inicio');
        END IF;
        IF v_obj_in.has('fecha_fin') THEN
            v_fecha_fin_str := v_obj_in.get_string('fecha_fin');
        END IF;

        BEGIN
            v_fecha := TO_DATE(TRIM(v_fecha_str), 'YYYY-MM-DD');
        EXCEPTION
            WHEN OTHERS THEN
                v_fecha := TRUNC(SYSDATE);
        END;

        BEGIN
            v_fecha_inicio := TO_DATE(TRIM(NVL(v_fecha_ini_str, v_fecha_str)), 'YYYY-MM-DD');
        EXCEPTION
            WHEN OTHERS THEN
                v_fecha_inicio := v_fecha;
        END;

        BEGIN
            v_fecha_fin := TO_DATE(TRIM(NVL(v_fecha_fin_str, NVL(v_fecha_str, v_fecha_ini_str))), 'YYYY-MM-DD');
        EXCEPTION
            WHEN OTHERS THEN
                v_fecha_fin := v_fecha_inicio;
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

        -- Telemetría
        v_traza_activa := uti_manejo_trazas_pkg.f_debe_trazar(
            p_nombre_paquete => 'pkgln_directorio_profesionales',
            p_nombre_metodo  => 'p_consultar_disponibilidad',
            p_id_usuario     => v_id_usuario_ejecutor,
            p_id_config_out  => v_id_config_traza,
            p_nivel_out      => v_nivel_detalle_traza,
            p_grabar_pay_out => v_grabar_payloads_traza
        );

        IF v_traza_activa THEN
            uti_manejo_trazas_pkg.p_iniciar_traza(
                p_nombre_paquete   => 'pkgln_directorio_profesionales',
                p_nombre_metodo    => 'p_consultar_disponibilidad',
                p_id_config        => v_id_config_traza,
                p_id_usuario       => v_id_usuario_ejecutor,
                p_codigo_traza     => v_codigo_traza,
                p_ip_origen        => SYS_CONTEXT('USERENV', 'IP_ADDRESS'),
                p_json_entrada     => p_json_entrada,
                p_grabar_payload   => v_grabar_payloads_traza,
                p_id_ejecucion_out => v_id_traza_ejecucion
            );
        END IF;

        -- Orquestación según tipo de vista
        IF v_tipo_vista = 'RANGO' THEN
            DECLARE
                v_f_ini             DATE := TRUNC(v_fecha_inicio);
                v_f_fin             DATE := TRUNC(v_fecha_fin);
                v_f_cur             DATE;
                v_json_dia          CLOB;
                v_obj_dia           JSON_OBJECT_T;
                v_slots_arr         JSON_ARRAY_T;
                v_dias_arr          JSON_ARRAY_T := JSON_ARRAY_T();
                v_res_obj           JSON_OBJECT_T := JSON_OBJECT_T();
                v_total_slots_rango NUMBER := 0;
                v_total_slots_dia   NUMBER;
            BEGIN
                IF v_f_fin < v_f_ini THEN
                    v_f_fin := v_f_ini;
                END IF;
                IF (v_f_fin - v_f_ini) > 365 THEN
                    v_f_fin := v_f_ini + 365;
                END IF;

                v_f_cur := v_f_ini;
                WHILE v_f_cur <= v_f_fin LOOP
                    p_calcular_disponibilidad_dia(
                        p_id_usuario            => v_id_usuario,
                        p_fecha                 => v_f_cur,
                        p_id_convenio           => v_id_convenio,
                        p_id_tipo_aseguramiento => v_id_tipo_aseguramiento,
                        p_modalidad             => v_modalidad,
                        p_json_salida           => v_json_dia
                    );

                    IF v_json_dia IS NOT NULL THEN
                        BEGIN
                            v_obj_dia := JSON_OBJECT_T.parse(v_json_dia);
                            IF v_obj_dia.has('slots') THEN
                                v_slots_arr := v_obj_dia.get_array('slots');
                                IF v_slots_arr IS NOT NULL AND v_slots_arr.get_size > 0 THEN
                                    v_total_slots_dia := v_obj_dia.get_number('total_slots');
                                    v_total_slots_rango := v_total_slots_rango + NVL(v_total_slots_dia, v_slots_arr.get_size);
                                    v_dias_arr.append(v_obj_dia);
                                END IF;
                            END IF;
                        EXCEPTION
                            WHEN OTHERS THEN
                                NULL;
                        END;
                    END IF;

                    v_f_cur := v_f_cur + 1;
                END LOOP;

                v_res_obj.put('codigo', 0);
                v_res_obj.put('mensaje', 'Rango consultado exitosamente');
                v_res_obj.put('id_usuario', v_id_usuario);
                v_res_obj.put('fecha_inicio', TO_CHAR(v_f_ini, 'YYYY-MM-DD'));
                v_res_obj.put('fecha_fin', TO_CHAR(v_f_fin, 'YYYY-MM-DD'));
                v_res_obj.put('total_slots_rango', v_total_slots_rango);
                v_res_obj.put('dias_disponibles', v_dias_arr);
                p_json_salida := v_res_obj.to_clob();
            END;

        ELSIF v_tipo_vista = 'SEMANA' THEN
            DECLARE
                v_dias_arr JSON_ARRAY_T := JSON_ARRAY_T();
                v_json_dia CLOB;
                v_fecha_actual DATE := TRUNC(v_fecha);
            BEGIN
                FOR i IN 0..6 LOOP
                    p_calcular_disponibilidad_dia(
                        p_id_usuario            => v_id_usuario,
                        p_fecha                 => v_fecha_actual + i,
                        p_id_convenio           => v_id_convenio,
                        p_id_tipo_aseguramiento => v_id_tipo_aseguramiento,
                        p_modalidad             => v_modalidad,
                        p_json_salida           => v_json_dia
                    );
                    v_dias_arr.append(JSON_ELEMENT_T.parse(v_json_dia));
                END LOOP;

                DECLARE
                    v_sem_obj JSON_OBJECT_T := JSON_OBJECT_T();
                BEGIN
                    v_sem_obj.put('codigo', 0);
                    v_sem_obj.put('mensaje', 'Disponibilidad semanal recuperada exitosamente');
                    v_sem_obj.put('id_usuario', v_id_usuario);
                    v_sem_obj.put('fecha_inicio', TO_CHAR(v_fecha_actual, 'YYYY-MM-DD'));
                    v_sem_obj.put('fecha_fin', TO_CHAR(v_fecha_actual + 6, 'YYYY-MM-DD'));
                    v_sem_obj.put('semana', v_dias_arr);
                    p_json_salida := v_sem_obj.to_clob();
                END;
            END;

        ELSE
            -- Vista diaria por defecto
            p_calcular_disponibilidad_dia(
                p_id_usuario            => v_id_usuario,
                p_fecha                 => v_fecha,
                p_id_convenio           => v_id_convenio,
                p_id_tipo_aseguramiento => v_id_tipo_aseguramiento,
                p_modalidad             => v_modalidad,
                p_json_salida           => p_json_salida
            );
        END IF;

        -- Cierre de telemetría
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

            IF v_traza_activa AND v_id_traza_ejecucion IS NOT NULL THEN
                uti_manejo_trazas_pkg.p_finalizar_traza_error(
                    p_id_ejecucion  => v_id_traza_ejecucion,
                    p_fecha_inicio  => v_fecha_inicio_traza,
                    p_codigo_error  => SQLCODE,
                    p_mensaje_error => SQLERRM
                );
            END IF;

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
        v_res_err JSON_OBJECT_T;
    BEGIN
        pkgcn_directorio_profesionales.p_consultar_filtros_catalogo_json(
            p_json_entrada => p_json_entrada,
            p_json_salida  => p_json_salida
        );
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

            v_res_err := JSON_OBJECT_T();
            v_res_err.put('codigo', -20000);
            v_res_err.put('error', -20000);
            v_res_err.put('mensaje', 'Error al consultar filtros: ' || vro_error.mensaje_error);
            p_json_salida := v_res_err.to_clob();
    END p_consultar_filtros;

    -- 4. Consultar únicamente los intervalos disponibles de un día en formato 12h AM/PM
    -- Retorna: [{"INTERVALO":"08:20 PM"},{"INTERVALO":"08:40 PM"},...]
    PROCEDURE p_consultar_intervalos_dia (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_id_usuario            NUMBER;
        v_fecha_str             VARCHAR2(20);
        v_fecha                 DATE;
        v_aseg_letra            VARCHAR2(5);
        v_mod_letra             VARCHAR2(5);
        v_id_tipo_aseguramiento NUMBER := 1;
        v_modalidad             VARCHAR2(1) := 'V';
        v_id_convenio           NUMBER;

        v_json_dia_completo     CLOB;
        v_obj_dia               JSON_OBJECT_T;
        v_slots_arr             JSON_ARRAY_T;
        v_slot_item             JSON_OBJECT_T;
        v_hora_inicio           VARCHAR2(10);
        v_disponible            NUMBER;
        v_hora_12h              VARCHAR2(20);

        v_resultado_arr         JSON_ARRAY_T := JSON_ARRAY_T();
        v_item_res              JSON_OBJECT_T;
    BEGIN
        IF p_json_entrada IS NULL THEN
            p_json_salida := TO_CLOB('[]');
            RETURN;
        END IF;

        v_id_usuario  := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_usuario'));
        v_fecha_str   := TRIM(JSON_VALUE(p_json_entrada, '$.fecha'));
        v_aseg_letra  := UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.tipo_aseguramiento')));
        v_mod_letra   := UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.clase_atencion')));
        v_id_convenio := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio'));

        IF v_id_usuario IS NULL OR v_fecha_str IS NULL THEN
            p_json_salida := TO_CLOB('[]');
            RETURN;
        END IF;

        BEGIN
            v_fecha := TO_DATE(v_fecha_str, 'YYYY-MM-DD');
        EXCEPTION
            WHEN OTHERS THEN
                p_json_salida := TO_CLOB('[]');
                RETURN;
        END;

        -- Regla: Tipo de aseguramiento: (V)oluntario = 1 por defecto, (O)bligatorio = 2
        IF v_aseg_letra = 'O' THEN
            v_id_tipo_aseguramiento := 2;
        ELSE
            v_id_tipo_aseguramiento := 1;
        END IF;

        -- Regla: Clase de atención: (V)irtual por defecto, (D)omiciliario
        IF v_mod_letra = 'D' THEN
            v_modalidad := 'D';
        ELSE
            v_modalidad := 'V';
        END IF;

        -- Ejecutar la lógica de disponibilidad en memoria
        p_calcular_disponibilidad_dia(
            p_id_usuario            => v_id_usuario,
            p_fecha                 => v_fecha,
            p_id_convenio           => v_id_convenio,
            p_id_tipo_aseguramiento => v_id_tipo_aseguramiento,
            p_modalidad             => v_modalidad,
            p_json_salida           => v_json_dia_completo
        );

        IF v_json_dia_completo IS NULL THEN
            p_json_salida := TO_CLOB('[]');
            RETURN;
        END IF;

        v_obj_dia := JSON_OBJECT_T.parse(v_json_dia_completo);
        IF NOT v_obj_dia.has('slots') THEN
            p_json_salida := TO_CLOB('[]');
            RETURN;
        END IF;

        v_slots_arr := v_obj_dia.get_array('slots');
        IF v_slots_arr IS NULL OR v_slots_arr.get_size = 0 THEN
            p_json_salida := TO_CLOB('[]');
            RETURN;
        END IF;

        FOR i IN 0 .. (v_slots_arr.get_size - 1) LOOP
            v_slot_item := JSON_OBJECT_T(v_slots_arr.get(i));
            v_disponible := 1;
            IF v_slot_item.has('disponible') THEN
                v_disponible := v_slot_item.get_number('disponible');
            END IF;

            IF v_disponible = 1 AND v_slot_item.has('hora_inicio') THEN
                v_hora_inicio := v_slot_item.get_string('hora_inicio');
                
                BEGIN
                    v_hora_12h := TO_CHAR(TO_DATE(v_hora_inicio, 'HH24:MI'), 'HH:MI AM');
                EXCEPTION
                    WHEN OTHERS THEN
                        v_hora_12h := v_hora_inicio;
                END;

                v_item_res := JSON_OBJECT_T();
                v_item_res.put('INTERVALO', v_hora_12h);
                v_resultado_arr.append(v_item_res);
            END IF;
        END LOOP;

        p_json_salida := v_resultado_arr.to_clob();
    EXCEPTION
        WHEN OTHERS THEN
            p_json_salida := TO_CLOB('[]');
    END p_consultar_intervalos_dia;

    -- 5. Consultar intervalos disponibles en un rango de fechas con formato dd/mm/yyyy
    -- Retorna: [{"fecha":"27/10/2026","intervalos":[{"INTERVALO":"08:20 PM"},...]},...]
    PROCEDURE p_consultar_intervalos_rango (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_id_usuario            NUMBER;
        v_fecha_ini_str         VARCHAR2(20);
        v_fecha_fin_str         VARCHAR2(20);
        v_fecha_inicio          DATE;
        v_fecha_fin             DATE;
        v_fecha_cur             DATE;
        v_aseg_letra            VARCHAR2(5);
        v_mod_letra             VARCHAR2(5);
        v_id_tipo_aseguramiento NUMBER := 1;
        v_modalidad             VARCHAR2(1) := 'V';
        v_id_convenio           NUMBER;
        v_solo_disp_str         VARCHAR2(5);
        v_solo_disp             BOOLEAN := TRUE;

        v_json_dia_completo     CLOB;
        v_obj_dia               JSON_OBJECT_T;
        v_slots_arr             JSON_ARRAY_T;
        v_slot_item             JSON_OBJECT_T;
        v_hora_inicio           VARCHAR2(10);
        v_disponible            NUMBER;
        v_hora_12h              VARCHAR2(20);

        v_resultado_arr         JSON_ARRAY_T := JSON_ARRAY_T();
        v_intervalos_arr        JSON_ARRAY_T;
        v_dia_obj               JSON_OBJECT_T;
        v_item_res              JSON_OBJECT_T;
    BEGIN
        IF p_json_entrada IS NULL THEN
            p_json_salida := TO_CLOB('[]');
            RETURN;
        END IF;

        v_id_usuario    := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_usuario'));
        v_fecha_ini_str := TRIM(JSON_VALUE(p_json_entrada, '$.fecha_inicio'));
        IF v_fecha_ini_str IS NULL THEN
            v_fecha_ini_str := TRIM(JSON_VALUE(p_json_entrada, '$.fecha'));
        END IF;
        v_fecha_fin_str := TRIM(JSON_VALUE(p_json_entrada, '$.fecha_fin'));
        v_aseg_letra    := UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.tipo_aseguramiento')));
        v_mod_letra     := UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.clase_atencion')));
        v_id_convenio   := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio'));
        v_solo_disp_str := UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.solo_disponibles')));

        IF v_id_usuario IS NULL OR v_fecha_ini_str IS NULL THEN
            p_json_salida := TO_CLOB('[]');
            RETURN;
        END IF;

        BEGIN
            IF INSTR(v_fecha_ini_str, '/') > 0 THEN
                v_fecha_inicio := TO_DATE(v_fecha_ini_str, 'DD/MM/YYYY');
            ELSE
                v_fecha_inicio := TO_DATE(v_fecha_ini_str, 'YYYY-MM-DD');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                p_json_salida := TO_CLOB('[]');
                RETURN;
        END;

        IF v_fecha_fin_str IS NOT NULL THEN
            BEGIN
                IF INSTR(v_fecha_fin_str, '/') > 0 THEN
                    v_fecha_fin := TO_DATE(v_fecha_fin_str, 'DD/MM/YYYY');
                ELSE
                    v_fecha_fin := TO_DATE(v_fecha_fin_str, 'YYYY-MM-DD');
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    v_fecha_fin := v_fecha_inicio;
            END;
        ELSE
            v_fecha_fin := v_fecha_inicio;
        END IF;

        IF v_fecha_fin < v_fecha_inicio THEN
            DECLARE
                v_tmp DATE := v_fecha_inicio;
            BEGIN
                v_fecha_inicio := v_fecha_fin;
                v_fecha_fin := v_tmp;
            END;
        END IF;

        IF (v_fecha_fin - v_fecha_inicio) > 365 THEN
            v_fecha_fin := v_fecha_inicio + 365;
        END IF;

        IF v_aseg_letra = 'O' THEN
            v_id_tipo_aseguramiento := 2;
        ELSE
            v_id_tipo_aseguramiento := 1;
        END IF;

        IF v_mod_letra = 'D' THEN
            v_modalidad := 'D';
        ELSE
            v_modalidad := 'V';
        END IF;

        IF v_solo_disp_str = 'N' THEN
            v_solo_disp := FALSE;
        ELSE
            v_solo_disp := TRUE;
        END IF;

        v_fecha_cur := TRUNC(v_fecha_inicio);
        WHILE v_fecha_cur <= TRUNC(v_fecha_fin) LOOP
            v_intervalos_arr := JSON_ARRAY_T();

            p_calcular_disponibilidad_dia(
                p_id_usuario            => v_id_usuario,
                p_fecha                 => v_fecha_cur,
                p_id_convenio           => v_id_convenio,
                p_id_tipo_aseguramiento => v_id_tipo_aseguramiento,
                p_modalidad             => v_modalidad,
                p_json_salida           => v_json_dia_completo
            );

            IF v_json_dia_completo IS NOT NULL THEN
                BEGIN
                    v_obj_dia := JSON_OBJECT_T.parse(v_json_dia_completo);
                    IF v_obj_dia.has('slots') THEN
                        v_slots_arr := v_obj_dia.get_array('slots');
                        IF v_slots_arr IS NOT NULL AND v_slots_arr.get_size > 0 THEN
                            FOR i IN 0 .. (v_slots_arr.get_size - 1) LOOP
                                v_slot_item := JSON_OBJECT_T(v_slots_arr.get(i));
                                v_disponible := 1;
                                IF v_slot_item.has('disponible') THEN
                                    v_disponible := v_slot_item.get_number('disponible');
                                END IF;

                                IF v_disponible = 1 AND v_slot_item.has('hora_inicio') THEN
                                    v_hora_inicio := v_slot_item.get_string('hora_inicio');
                                    BEGIN
                                        v_hora_12h := TO_CHAR(TO_DATE(v_hora_inicio, 'HH24:MI'), 'HH:MI AM');
                                    EXCEPTION
                                        WHEN OTHERS THEN
                                            v_hora_12h := v_hora_inicio;
                                    END;

                                    v_item_res := JSON_OBJECT_T();
                                    v_item_res.put('INTERVALO', v_hora_12h);
                                    v_intervalos_arr.append(v_item_res);
                                END IF;
                            END LOOP;
                        END IF;
                    END IF;
                EXCEPTION
                    WHEN OTHERS THEN
                        NULL;
                END;
            END IF;

            IF NOT v_solo_disp OR v_intervalos_arr.get_size > 0 THEN
                v_dia_obj := JSON_OBJECT_T();
                v_dia_obj.put('fecha', TO_CHAR(v_fecha_cur, 'DD/MM/YYYY'));
                v_dia_obj.put('intervalos', v_intervalos_arr);
                v_resultado_arr.append(v_dia_obj);
            END IF;

            v_fecha_cur := v_fecha_cur + 1;
        END LOOP;

        p_json_salida := v_resultado_arr.to_clob();
    EXCEPTION
        WHEN OTHERS THEN
            p_json_salida := TO_CLOB('[]');
    END p_consultar_intervalos_rango;

    -- 6. Orquestar la actualización de slots de cita (Marcar/Desmarcar) en el bitmap
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
                v_duracion_min := 20;
            END IF;
        END IF;

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

        v_idx_inicio := TRUNC(v_min_inicio / 5) + 1;
        v_idx_fin    := TRUNC(v_min_fin / 5);

        IF v_idx_inicio < 1 THEN v_idx_inicio := 1; END IF;
        IF v_idx_fin > 288 THEN v_idx_fin := 288; END IF;

        IF v_tipo_operacion = 'M' THEN
            v_caracter_bit := '1';
        ELSE
            v_caracter_bit := '0';
        END IF;

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

        -- Invocación DML mono-tabla
        pkgca_tkr_disponibilidad_bitmap.p_actualizar_bitmap_ocupado(
            p_json_entrada    => v_json_ca,
            p_filas_afectadas => v_filas_afectadas
        );

        -- Confirmación controlada exclusiva de la capa pkgln_
        p_do_commit('pkgln_directorio_profesionales.p_actualizar_slots_cita');

        IF v_traza_activa AND v_id_traza_ejecucion IS NOT NULL THEN
            uti_manejo_trazas_pkg.p_finalizar_traza(
                p_id_ejecucion   => v_id_traza_ejecucion,
                p_fecha_inicio   => v_fecha_inicio_traza,
                p_json_salida    => '{"codigo": 0, "filas_afectadas": ' || v_filas_afectadas || '}',
                p_grabar_payload => v_grabar_payloads_traza
            );
        END IF;

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

    -- 7. Marcar o desmarcar un rango explícito de slots pasando id_usuario, fecha_hora y duracion_minutos
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

        v_obj_ca                JSON_OBJECT_T;
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

        v_id_usuario            := NVL(TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_profesional')),
                                       TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_usuario')));
        v_fecha_hora_str        := TRIM(JSON_VALUE(p_json_entrada, '$.fecha_hora'));
        v_duracion_min          := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.duracion_minutos'));
        
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

        v_idx_inicio := TRUNC(v_min_inicio / 5) + 1;
        v_idx_fin    := TRUNC(v_min_fin / 5);

        IF v_idx_inicio < 1 THEN v_idx_inicio := 1; END IF;
        IF v_idx_fin > 288 THEN v_idx_fin := 288; END IF;

        IF v_tipo_operacion = 'M' THEN
            v_caracter_bit := '1';
        ELSE
            v_caracter_bit := '0';
        END IF;

        v_obj_ca := JSON_OBJECT_T();
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

        pkgca_tkr_disponibilidad_bitmap.p_actualizar_bitmap_ocupado(
            p_json_entrada    => v_json_ca,
            p_filas_afectadas => v_filas_afectadas
        );

        p_do_commit('pkgln_directorio_profesionales.p_marcar_desmarcar_slots');

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

    -- 8. Consultar detalle del profesional seleccionado
    PROCEDURE p_consultar_detalle_profesional (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_obj_in              JSON_OBJECT_T;
        v_res_err             JSON_OBJECT_T;
        v_id_usuario          NUMBER(12);
        v_id_usuario_ejecutor NUMBER(12);
        v_codigo_traza        VARCHAR2(100);

        v_traza_activa          BOOLEAN := FALSE;
        v_id_config_traza       NUMBER(12) := NULL;
        v_id_traza_ejecucion    NUMBER(12) := NULL;
        v_nivel_detalle_traza   VARCHAR2(30) := 'COMPLETO';
        v_grabar_payloads_traza NUMBER(1) := 1;
        v_fecha_inicio_traza    TIMESTAMP := SYSTIMESTAMP;
    BEGIN
        IF p_json_entrada IS NULL OR DBMS_LOB.GETLENGTH(p_json_entrada) = 0 THEN
            v_res_err := JSON_OBJECT_T();
            v_res_err.put('codigo', -20001);
            v_res_err.put('error', -20001);
            v_res_err.put('mensaje', 'Payload requerido');
            p_json_salida := v_res_err.to_clob();
            RETURN;
        END IF;

        v_obj_in     := JSON_OBJECT_T.parse(p_json_entrada);
        v_id_usuario := NVL(v_obj_in.get_number('id_usuario'), v_obj_in.get_number('id'));

        IF v_id_usuario IS NULL THEN
            v_res_err := JSON_OBJECT_T();
            v_res_err.put('codigo', -20002);
            v_res_err.put('error', -20002);
            v_res_err.put('mensaje', 'El id_usuario o id del profesional es obligatorio');
            p_json_salida := v_res_err.to_clob();
            RETURN;
        END IF;

        IF v_obj_in.has('id_usuario_ejecutor') THEN
            v_id_usuario_ejecutor := v_obj_in.get_number('id_usuario_ejecutor');
        END IF;
        IF v_obj_in.has('codigo_traza') THEN
            v_codigo_traza := v_obj_in.get_string('codigo_traza');
        END IF;
        IF v_codigo_traza IS NULL THEN
            v_codigo_traza := RAWTOHEX(SYS_GUID());
        END IF;

        -- Telemetría institucional
        v_traza_activa := uti_manejo_trazas_pkg.f_debe_trazar(
            p_nombre_paquete => 'PKGLN_DIRECTORIO_PROFESIONALES',
            p_nombre_metodo  => 'p_consultar_detalle_profesional',
            p_id_usuario     => v_id_usuario_ejecutor,
            p_id_config_out  => v_id_config_traza,
            p_nivel_out      => v_nivel_detalle_traza,
            p_grabar_pay_out => v_grabar_payloads_traza
        );

        IF v_traza_activa THEN
            uti_manejo_trazas_pkg.p_iniciar_traza(
                p_nombre_paquete   => 'PKGLN_DIRECTORIO_PROFESIONALES',
                p_nombre_metodo    => 'p_consultar_detalle_profesional',
                p_id_config        => v_id_config_traza,
                p_id_usuario       => v_id_usuario_ejecutor,
                p_codigo_traza     => v_codigo_traza,
                p_ip_origen        => SYS_CONTEXT('USERENV', 'IP_ADDRESS'),
                p_json_entrada     => p_json_entrada,
                p_grabar_payload   => v_grabar_payloads_traza,
                p_id_ejecucion_out => v_id_traza_ejecucion
            );
        END IF;

        -- Delegar consulta relacional multi-tabla a pkgcn_
        pkgcn_directorio_profesionales.p_consultar_detalle_profesional(
            p_json_entrada => p_json_entrada,
            p_json_salida  => p_json_salida
        );

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
            vro_error.tipo                := 'E';
            vro_error.nombre_programa     := 'PKGLN_DIRECTORIO_PROFESIONALES';
            vro_error.nombre_metodo       := 'p_consultar_detalle_profesional';
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

            v_res_err := JSON_OBJECT_T();
            v_res_err.put('codigo', -20000);
            v_res_err.put('error', -20000);
            v_res_err.put('mensaje', 'Error al consultar detalle del profesional: ' || vro_error.mensaje_error);
            p_json_salida := v_res_err.to_clob();
    END p_consultar_detalle_profesional;

    -- 9. Consultar profesionales sin disponibilidad horaria en un rango de fechas agrupados por especialidad
    PROCEDURE p_consultar_sin_disponibilidad (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_obj_in                    JSON_OBJECT_T;
        v_res_out                   JSON_OBJECT_T;
        v_res_err                   JSON_OBJECT_T;
        v_arr_especialidades        JSON_ARRAY_T := JSON_ARRAY_T();
        v_arr_doctores              JSON_ARRAY_T;
        v_obj_esp                   JSON_OBJECT_T;
        v_obj_doc                   JSON_OBJECT_T;

        v_fecha_ini_str             VARCHAR2(30);
        v_fecha_fin_str             VARCHAR2(30);
        v_fecha_inicio              DATE;
        v_fecha_fin                 DATE;
        v_id_convenio               NUMBER(12);
        v_id_tipo_aseguramiento     NUMBER(12);
        v_modalidad                 VARCHAR2(2);
        v_id_especialidad_fil       NUMBER(12);

        v_id_usuario_ejecutor       NUMBER(12) := 1;
        v_codigo_traza              VARCHAR2(100);
        v_id_traza_ejecucion        NUMBER(12);
        v_id_config_traza           NUMBER(12);
        v_nivel_detalle_traza       VARCHAR2(20);
        v_grabar_payloads_traza     VARCHAR2(1);
        v_traza_activa              BOOLEAN;
        v_fecha_inicio_traza        TIMESTAMP := SYSTIMESTAMP;

        -- Cursor de todas las especialidades del sistema
        CURSOR c_todas_especialidades IS
            SELECT e.id AS id_especialidad,
                   e.nombre_especialidad
              FROM tkr_especialidades e
             WHERE (v_id_especialidad_fil IS NULL OR e.id = v_id_especialidad_fil)
             ORDER BY e.nombre_especialidad ASC;

        -- Cursor de médicos habilitados
        CURSOR c_profesionales IS
            SELECT u.id AS id_usuario,
                   TRIM(u.nombres || ' ' || u.apellidos) AS nombre_completo,
                   u.correo_electronico,
                   u.telefono
              FROM tkr_usuarios u
             WHERE u.estado = 'A'
               AND NVL(u.ocultar_directorio, 'N') = 'N'
             ORDER BY u.nombres, u.apellidos;

        -- Cursor de especialidades asignadas al médico
        CURSOR c_especialidades_doc (cp_id_usuario NUMBER) IS
            SELECT eu.id_especialidad,
                   e.nombre_especialidad
              FROM tkr_especialidades_usuario eu,
                   tkr_especialidades         e
             WHERE eu.id_usuario      = cp_id_usuario
               AND e.id               = eu.id_especialidad;

        v_payload_disp              JSON_OBJECT_T;
        v_salida_disp               CLOB;
        v_obj_disp                  JSON_OBJECT_T;
        v_total_slots_rango         NUMBER := 0;
        v_dias_servicio             VARCHAR2(200);
        v_motivo                    VARCHAR2(200);

        TYPE t_doctor_sin_disp IS RECORD (
            id_usuario      NUMBER(12),
            nombre_completo VARCHAR2(200),
            correo          VARCHAR2(200),
            telefono        VARCHAR2(50),
            days_of_service VARCHAR2(200),
            motivo          VARCHAR2(200),
            id_especialidad NUMBER(12),
            nombre_esp      VARCHAR2(150)
        );
        TYPE t_tab_doctores IS TABLE OF t_doctor_sin_disp INDEX BY PLS_INTEGER;
        v_doctores_sin_disp         t_tab_doctores;
        v_idx_doc                   PLS_INTEGER := 0;

        v_total_sin_disp            NUMBER := 0;
        v_total_esp_sin_medicos     NUMBER := 0;
        v_total_med_sin_cupos       NUMBER := 0;
        v_docs_en_esp               PLS_INTEGER := 0;
    BEGIN
        IF p_json_entrada IS NOT NULL THEN
            v_obj_in := JSON_OBJECT_T.parse(p_json_entrada);
            IF v_obj_in.has('fecha_inicio') THEN
                v_fecha_ini_str := v_obj_in.get_string('fecha_inicio');
            END IF;
            IF v_obj_in.has('fecha_fin') THEN
                v_fecha_fin_str := v_obj_in.get_string('fecha_fin');
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
            IF v_obj_in.has('codigo_traza') THEN
                v_codigo_traza := v_obj_in.get_string('codigo_traza');
            END IF;
            IF v_obj_in.has('id_usuario_ejecutor') THEN
                v_id_usuario_ejecutor := v_obj_in.get_number('id_usuario_ejecutor');
            END IF;
            IF v_obj_in.has('id_especialidad') THEN
                v_id_especialidad_fil := v_obj_in.get_number('id_especialidad');
            END IF;
        END IF;

        IF v_codigo_traza IS NULL THEN
            v_codigo_traza := RAWTOHEX(SYS_GUID());
        END IF;

        IF v_fecha_ini_str IS NOT NULL THEN
            IF INSTR(v_fecha_ini_str, '/') > 0 THEN
                v_fecha_inicio := TRUNC(TO_DATE(SUBSTR(v_fecha_ini_str, 1, 10), 'DD/MM/YYYY'));
            ELSE
                v_fecha_inicio := TRUNC(TO_DATE(SUBSTR(v_fecha_ini_str, 1, 10), 'YYYY-MM-DD'));
            END IF;
        ELSE
            v_fecha_inicio := TRUNC(SYSDATE);
        END IF;

        IF v_fecha_fin_str IS NOT NULL THEN
            IF INSTR(v_fecha_fin_str, '/') > 0 THEN
                v_fecha_fin := TRUNC(TO_DATE(SUBSTR(v_fecha_fin_str, 1, 10), 'DD/MM/YYYY'));
            ELSE
                v_fecha_fin := TRUNC(TO_DATE(SUBSTR(v_fecha_fin_str, 1, 10), 'YYYY-MM-DD'));
            END IF;
        ELSE
            v_fecha_fin := v_fecha_inicio + 6;
        END IF;

        IF v_fecha_fin < v_fecha_inicio THEN
            v_fecha_fin := v_fecha_inicio;
        END IF;

        -- Telemetría
        v_traza_activa := uti_manejo_trazas_pkg.f_debe_trazar(
            p_nombre_paquete => 'PKGLN_DIRECTORIO_PROFESIONALES',
            p_nombre_metodo  => 'p_consultar_sin_disponibilidad',
            p_id_usuario     => v_id_usuario_ejecutor,
            p_id_config_out  => v_id_config_traza,
            p_nivel_out      => v_nivel_detalle_traza,
            p_grabar_pay_out => v_grabar_payloads_traza
        );

        IF v_traza_activa THEN
            uti_manejo_trazas_pkg.p_iniciar_traza(
                p_nombre_paquete   => 'PKGLN_DIRECTORIO_PROFESIONALES',
                p_nombre_metodo    => 'p_consultar_sin_disponibilidad',
                p_id_config        => v_id_config_traza,
                p_id_usuario       => v_id_usuario_ejecutor,
                p_codigo_traza     => v_codigo_traza,
                p_ip_origen        => SYS_CONTEXT('USERENV', 'IP_ADDRESS'),
                p_json_entrada     => p_json_entrada,
                p_grabar_payload   => v_grabar_payloads_traza,
                p_id_ejecucion_out => v_id_traza_ejecucion
            );
        END IF;

        -- 1. Evaluar disponibilidad de cada médico habilitado
        FOR r_prof IN c_profesionales LOOP
            v_payload_disp := JSON_OBJECT_T();
            v_payload_disp.put('id_usuario', r_prof.id_usuario);
            v_payload_disp.put('tipo_vista', 'RANGO');
            v_payload_disp.put('fecha_inicio', TO_CHAR(v_fecha_inicio, 'YYYY-MM-DD'));
            v_payload_disp.put('fecha_fin', TO_CHAR(v_fecha_fin, 'YYYY-MM-DD'));
            IF v_id_convenio IS NOT NULL THEN
                v_payload_disp.put('id_convenio', v_id_convenio);
            END IF;
            IF v_id_tipo_aseguramiento IS NOT NULL THEN
                v_payload_disp.put('id_tipo_aseguramiento', v_id_tipo_aseguramiento);
            END IF;
            IF v_modalidad IS NOT NULL THEN
                v_payload_disp.put('modalidad', v_modalidad);
            END IF;

            p_consultar_disponibilidad(
                p_json_entrada => v_payload_disp.to_clob(),
                p_json_salida  => v_salida_disp
            );

            v_obj_disp := JSON_OBJECT_T.parse(v_salida_disp);
            v_total_slots_rango := NVL(v_obj_disp.get_number('total_slots_rango'), 0);

            -- Si no tiene intervalos disponibles en el rango
            IF v_total_slots_rango = 0 THEN
                v_dias_servicio := pkgcn_directorio_profesionales.f_dias_servicio_profesional(
                    r_prof.id_usuario,
                    TO_CHAR(v_fecha_inicio, 'YYYY-MM-DD'),
                    TO_CHAR(v_fecha_fin, 'YYYY-MM-DD'),
                    v_id_convenio,
                    v_id_tipo_aseguramiento
                );

                IF v_dias_servicio IS NULL THEN
                    v_motivo := 'Sin horarios programados en el rango';
                ELSE
                    v_motivo := 'Horarios configurados (' || v_dias_servicio || ') pero sin slots libres';
                END IF;

                -- Asociar a las especialidades asignadas al médico
                FOR r_esp IN c_especialidades_doc(r_prof.id_usuario) LOOP
                    IF v_id_especialidad_fil IS NULL OR r_esp.id_especialidad = v_id_especialidad_fil THEN
                        v_idx_doc := v_idx_doc + 1;
                        v_doctores_sin_disp(v_idx_doc).id_usuario      := r_prof.id_usuario;
                        v_doctores_sin_disp(v_idx_doc).nombre_completo := r_prof.nombre_completo;
                        v_doctores_sin_disp(v_idx_doc).correo          := r_prof.correo_electronico;
                        v_doctores_sin_disp(v_idx_doc).telefono        := r_prof.telefono;
                        v_doctores_sin_disp(v_idx_doc).days_of_service := NVL(v_dias_servicio, 'Sin horarios');
                        v_doctores_sin_disp(v_idx_doc).motivo          := v_motivo;
                        v_doctores_sin_disp(v_idx_doc).id_especialidad := r_esp.id_especialidad;
                        v_doctores_sin_disp(v_idx_doc).nombre_esp      := r_esp.nombre_especialidad;
                    END IF;
                END LOOP;

                v_total_med_sin_cupos := v_total_med_sin_cupos + 1;
            END IF;
        END LOOP;

        -- 2. Recorrer TODAS las especialidades del sistema e incluir tanto las que no tienen médicos
        -- como las que tienen médicos con 0 cupos
        FOR r_todas IN c_todas_especialidades LOOP
            v_docs_en_esp := 0;
            v_arr_doctores := JSON_ARRAY_T();

            FOR j IN 1..v_idx_doc LOOP
                IF v_doctores_sin_disp(j).id_especialidad = r_todas.id_especialidad THEN
                    v_docs_en_esp := v_docs_en_esp + 1;
                    v_obj_doc := JSON_OBJECT_T();
                    v_obj_doc.put('id', v_doctores_sin_disp(j).id_usuario);
                    v_obj_doc.put('id_usuario', v_doctores_sin_disp(j).id_usuario);
                    v_obj_doc.put('fullName', v_doctores_sin_disp(j).nombre_completo);
                    v_obj_doc.put('nombre_completo', v_doctores_sin_disp(j).nombre_completo);
                    v_obj_doc.put('correo', v_doctores_sin_disp(j).correo);
                    v_obj_doc.put('telefono', v_doctores_sin_disp(j).telefono);
                    v_obj_doc.put('days_of_service', v_doctores_sin_disp(j).days_of_service);
                    v_obj_doc.put('motivo', v_doctores_sin_disp(j).motivo);
                    v_arr_doctores.append(v_obj_doc);
                END IF;
            END LOOP;

            -- Verificar si la especialidad tiene profesionales asignados en BD
            DECLARE
                v_cant_asignados NUMBER := 0;
            BEGIN
                SELECT COUNT(1)
                  INTO v_cant_asignados
                  FROM tkr_especialidades_usuario eu,
                       tkr_usuarios               u
                 WHERE eu.id_especialidad = r_todas.id_especialidad
                   AND u.id               = eu.id_usuario
                   AND u.estado           = 'A'
                   AND NVL(u.ocultar_directorio, 'N') = 'N';

                IF v_cant_asignados = 0 THEN
                    -- Caso: Especialidad sin médicos asignados
                    v_total_esp_sin_medicos := v_total_esp_sin_medicos + 1;
                    v_total_sin_disp        := v_total_sin_disp + 1;

                    v_obj_esp := JSON_OBJECT_T();
                    v_obj_esp.put('id_especialidad', r_todas.id_especialidad);
                    v_obj_esp.put('nombre_especialidad', r_todas.nombre_especialidad);
                    v_obj_esp.put('tiene_profesionales', false);
                    v_obj_esp.put('tipo', 'SIN_PROFESIONALES');
                    v_obj_esp.put('total_profesionales', 0);
                    v_obj_esp.put('profesionales', JSON_ARRAY_T());
                    v_arr_especialidades.append(v_obj_esp);

                ELSIF v_docs_en_esp > 0 THEN
                    -- Caso: Especialidad con médicos pero sin cupos libres en el rango
                    v_total_sin_disp := v_total_sin_disp + 1;

                    v_obj_esp := JSON_OBJECT_T();
                    v_obj_esp.put('id_especialidad', r_todas.id_especialidad);
                    v_obj_esp.put('nombre_especialidad', r_todas.nombre_especialidad);
                    v_obj_esp.put('tiene_profesionales', true);
                    v_obj_esp.put('tipo', 'CON_PROFESIONALES_SIN_DISPONIBILIDAD');
                    v_obj_esp.put('total_profesionales', v_docs_en_esp);
                    v_obj_esp.put('profesionales', v_arr_doctores);
                    v_arr_especialidades.append(v_obj_esp);
                END IF;
            END;
        END LOOP;

        v_res_out := JSON_OBJECT_T();
        v_res_out.put('codigo', 0);
        v_res_out.put('mensaje', 'Consulta de especialidades y profesionales sin disponibilidad completada exitosamente');
        v_res_out.put('fecha_inicio', TO_CHAR(v_fecha_inicio, 'YYYY-MM-DD'));
        v_res_out.put('fecha_fin', TO_CHAR(v_fecha_fin, 'YYYY-MM-DD'));
        v_res_out.put('total_sin_disponibilidad', v_total_sin_disp);
        v_res_out.put('total_especialidades_sin_medicos', v_total_esp_sin_medicos);
        v_res_out.put('total_medicos_sin_cupos', v_total_med_sin_cupos);
        v_res_out.put('especialidades', v_arr_especialidades);

        p_json_salida := v_res_out.to_clob();

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
            vro_error.tipo                := 'E';
            vro_error.nombre_programa     := 'PKGLN_DIRECTORIO_PROFESIONALES';
            vro_error.nombre_metodo       := 'p_consultar_sin_disponibilidad';
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

            v_res_err := JSON_OBJECT_T();
            v_res_err.put('codigo', -20000);
            v_res_err.put('error', -20000);
            v_res_err.put('mensaje', 'Error al consultar profesionales sin disponibilidad: ' || vro_error.mensaje_error);
            p_json_salida := v_res_err.to_clob();
    END p_consultar_sin_disponibilidad;

END pkgln_directorio_profesionales;
/
