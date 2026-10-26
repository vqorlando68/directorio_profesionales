CREATE OR REPLACE PACKAGE BODY pkgcn_directorio_profesionales AS
    /*
    || =========================================================================
    || Paquete: pkgcn_directorio_profesionales (Body)
    || Propósito: Implementación de casos de negocio multi-tabla para directorio
    ||            de profesionales y motor de disponibilidad horaria / bitmaps.
    || Estándar: oracle-plsql-architecture
    || =========================================================================
    */

    -- Función auxiliar interna para convertir hora HH24:MI a minutos del día (0..1439)
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

    -- Función auxiliar interna para convertir minutos del día a hora HH24:MI
    FUNCTION f_minutos_a_hora (p_minutos IN NUMBER) RETURN VARCHAR2 IS
        v_h NUMBER;
        v_m NUMBER;
    BEGIN
        v_h := TRUNC(p_minutos / 60);
        v_m := MOD(p_minutos, 60);
        RETURN LPAD(TO_CHAR(v_h), 2, '0') || ':' || LPAD(TO_CHAR(v_m), 2, '0');
    END f_minutos_a_hora;

    -- Función auxiliar para obtener código de día canónico TEKER ('LU', 'MA', 'MI', 'JU', 'VI', 'SA', 'DO')
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
                -- Respaldo numérico 1 = Domingo o 1 = Lunes según NLS
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

    -- 1. Consultar directorio paginado de profesionales habilitados con filtros
    PROCEDURE p_consultar_profesionales_json (
        p_id_especialidad       IN  NUMBER   DEFAULT NULL,
        p_id_convenio           IN  NUMBER   DEFAULT NULL,
        p_id_tipo_aseguramiento IN  NUMBER   DEFAULT NULL,
        p_modalidad             IN  VARCHAR2 DEFAULT NULL,
        p_busqueda              IN  VARCHAR2 DEFAULT NULL,
        p_pagina                IN  NUMBER   DEFAULT 1,
        p_registros_por_pagina  IN  NUMBER   DEFAULT 12,
        p_json_salida           OUT CLOB
    ) IS
        v_limite          NUMBER := NVL(p_registros_por_pagina, 12);
        v_pagina          NUMBER := GREATEST(NVL(p_pagina, 1), 1);
        v_offset          NUMBER;
        v_total_registros NUMBER := 0;
        v_total_paginas   NUMBER := 0;
        v_json_arr        CLOB;
    BEGIN
        IF v_limite <= 0 THEN
            v_limite := 12;
        END IF;
        v_offset := (v_pagina - 1) * v_limite;

        -- Conteo total de registros que satisfacen los filtros para paginación
        SELECT COUNT(1)
          INTO v_total_registros
          FROM tkr_usuarios u
         WHERE u.id_estado_usuario = 1
           -- Regla obligatoria: Rol médico en u.id_rol = 4 o en tkr_roles_usuario
           AND (
               u.id_rol = 4 
               OR EXISTS (SELECT 1 FROM tkr_roles_usuario ru WHERE ru.id_usuario = u.id AND ru.id_rol = 4)
           )
           -- Regla obligatoria: Que tenga al menos una franja horaria activa registrada
           AND EXISTS (
               SELECT 1 
                 FROM tkr_horarios_profesional h 
                WHERE h.id_usuario = u.id 
                  AND h.activo = 1
           )
           -- Filtro opcional por especialidad
           AND (
               p_id_especialidad IS NULL 
               OR EXISTS (
                   SELECT 1 
                     FROM tkr_especialidades_usuario ue 
                    WHERE ue.id_usuario = u.id 
                      AND ue.id_especialidad = p_id_especialidad
               )
           )
           -- Filtro opcional por convenio
           AND (
               p_id_convenio IS NULL
               OR EXISTS (
                   SELECT 1 
                     FROM tkr_horarios_profesional h
                    WHERE h.id_usuario = u.id
                      AND h.activo = 1
                      AND (h.id_convenio = p_id_convenio OR h.id_convenio IS NULL)
               )
           )
           -- Filtro opcional por tipo de aseguramiento (Voluntario / Obligatorio)
           AND (
               p_id_tipo_aseguramiento IS NULL
               OR EXISTS (
                   SELECT 1 
                     FROM tkr_horarios_profesional h
                    WHERE h.id_usuario = u.id
                      AND h.activo = 1
                      AND (h.id_tipo_aseguramiento = p_id_tipo_aseguramiento OR h.id_tipo_aseguramiento IS NULL)
               )
           )
           -- Filtro opcional por modalidad (Virtual 'V' / Domiciliaria 'D')
           AND (
               p_modalidad IS NULL
               OR EXISTS (
                   SELECT 1 
                     FROM tkr_franjas_profesional f
                    WHERE f.id_usuario = u.id
                      AND f.activo = 1
                      AND (f.modalidad = UPPER(TRIM(p_modalidad)) OR f.modalidad IS NULL)
               )
           )
           -- Filtro de búsqueda textual (nombre, apellidos o correo)
           AND (
               p_busqueda IS NULL
               OR UPPER(u.nombres || ' ' || u.apellidos) LIKE '%' || UPPER(TRIM(p_busqueda)) || '%'
               OR UPPER(u.correo_electronico) LIKE '%' || UPPER(TRIM(p_busqueda)) || '%'
           );

        v_total_paginas := CEIL(v_total_registros / v_limite);

        -- Consulta paginada con extracción JSON de profesionales
        SELECT COALESCE(
                   JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'id_usuario'       VALUE prof.id,
                           'nombre_completo'  VALUE TRIM(prof.nombres || ' ' || prof.apellidos),
                           'nombres'          VALUE prof.nombres,
                           'apellidos'        VALUE prof.apellidos,
                           'correo'           VALUE prof.correo_electronico,
                           'telefono'         VALUE prof.telefono,
                           'trabaja_festivos' VALUE NVL(prof.trabaja_festivos, 'N'),
                           'url_foto'         VALUE pkgcn_profesionales.f_url_foto_profesional(prof.id),
                           'especialidades'   VALUE (
                               SELECT JSON_ARRAYAGG(
                                          JSON_OBJECT(
                                              'id'     VALUE e.id,
                                              'nombre' VALUE e.nombre_especialidad
                                          )
                                          RETURNING CLOB
                                      )
                                 FROM tkr_especialidades_usuario ue,
                                      tkr_especialidades        e
                                WHERE ue.id_usuario = prof.id
                                  AND e.id          = ue.id_especialidad
                           ),
                           'modalidades'      VALUE (
                               SELECT JSON_ARRAYAGG(m.modalidad RETURNING CLOB)
                                  FROM (
                                      SELECT DISTINCT f.id_usuario, NVL(f.modalidad, 'TODAS') AS modalidad
                                        FROM tkr_franjas_profesional f
                                       WHERE f.activo = 1
                                  ) m
                                 WHERE m.id_usuario = prof.id
                           )
                       )
                       RETURNING CLOB
                   ),
                   TO_CLOB('[]')
               )
          INTO v_json_arr
          FROM (
              SELECT u.id,
                     u.nombres,
                     u.apellidos,
                     u.correo_electronico,
                     u.telefono,
                     u.trabaja_festivos
                FROM tkr_usuarios u
               WHERE u.id_estado_usuario = 1
                 AND (
                     u.id_rol = 4 
                     OR EXISTS (SELECT 1 FROM tkr_roles_usuario ru WHERE ru.id_usuario = u.id AND ru.id_rol = 4)
                 )
                 AND EXISTS (
                     SELECT 1 
                       FROM tkr_horarios_profesional h 
                      WHERE h.id_usuario = u.id 
                        AND h.activo = 1
                 )
                 AND (
                     p_id_especialidad IS NULL 
                     OR EXISTS (
                         SELECT 1 
                           FROM tkr_especialidades_usuario ue 
                          WHERE ue.id_usuario = u.id 
                            AND ue.id_especialidad = p_id_especialidad
                     )
                 )
                 AND (
                     p_id_convenio IS NULL
                     OR EXISTS (
                         SELECT 1 
                           FROM tkr_horarios_profesional h
                          WHERE h.id_usuario = u.id
                            AND h.activo = 1
                            AND (h.id_convenio = p_id_convenio OR h.id_convenio IS NULL)
                     )
                 )
                 AND (
                     p_id_tipo_aseguramiento IS NULL
                     OR EXISTS (
                         SELECT 1 
                           FROM tkr_horarios_profesional h
                          WHERE h.id_usuario = u.id
                            AND h.activo = 1
                            AND (h.id_tipo_aseguramiento = p_id_tipo_aseguramiento OR h.id_tipo_aseguramiento IS NULL)
                     )
                 )
                 AND (
                     p_modalidad IS NULL
                     OR EXISTS (
                         SELECT 1 
                           FROM tkr_franjas_profesional f
                          WHERE f.id_usuario = u.id
                            AND f.activo = 1
                            AND (f.modalidad = UPPER(TRIM(p_modalidad)) OR f.modalidad IS NULL)
                     )
                 )
                 AND (
                     p_busqueda IS NULL
                     OR UPPER(u.nombres || ' ' || u.apellidos) LIKE '%' || UPPER(TRIM(p_busqueda)) || '%'
                     OR UPPER(u.correo_electronico) LIKE '%' || UPPER(TRIM(p_busqueda)) || '%'
                 )
               ORDER BY u.nombres ASC, u.apellidos ASC
              OFFSET v_offset ROWS
               FETCH NEXT v_limite ROWS ONLY
          ) prof;

        SELECT JSON_OBJECT(
                   'codigo'           VALUE 0,
                   'mensaje'          VALUE 'Directorio consultado exitosamente',
                   'total_registros'  VALUE v_total_registros,
                   'total_paginas'    VALUE v_total_paginas,
                   'pagina_actual'    VALUE v_pagina,
                   'registros_pagina' VALUE v_limite,
                   'profesionales'    VALUE JSON_QUERY(v_json_arr, '$' RETURNING CLOB)
                   RETURNING CLOB
               )
          INTO p_json_salida
          FROM DUAL;
    END p_consultar_profesionales_json;

    -- 2. Consultar slots y vector de disponibilidad para un profesional y fecha específica
    PROCEDURE p_consultar_slots_dia_json (
        p_id_usuario            IN  NUMBER,
        p_fecha                 IN  DATE,
        p_id_convenio           IN  NUMBER   DEFAULT NULL,
        p_id_tipo_aseguramiento IN  NUMBER   DEFAULT 1,
        p_modalidad             IN  VARCHAR2 DEFAULT 'V',
        p_json_salida           OUT CLOB
    ) IS
        v_dia_semana        VARCHAR2(10);
        v_trabaja_festivos  VARCHAR2(1) := 'N';
        v_es_festivo        BOOLEAN := FALSE;
        v_es_domingo        BOOLEAN := FALSE;
        v_bloqueado_ausencia BOOLEAN := FALSE;
        v_tipo_horario_aplica VARCHAR2(30) := 'NINGUNO';
        v_duracion_min      NUMBER := 20;
        v_bitmap            VARCHAR2(288) := RPAD('0', 288, '0');
        v_slots_arr         JSON_ARRAY_T := JSON_ARRAY_T();
        v_slot_obj          JSON_OBJECT_T;
        v_total_slots       NUMBER := 0;

        -- Cursor de turnos según jerarquía
        CURSOR c_turnos (p_tipo_vigencia IN VARCHAR2) IS
            SELECT h.id,
                   h.hora_desde,
                   h.hora_hasta,
                   h.id_convenio,
                   h.id_tipo_aseguramiento
              FROM tkr_horarios_profesional h
             WHERE h.id_usuario = p_id_usuario
               AND h.dia_semana = v_dia_semana
               AND h.activo = 1
               AND (
                   p_id_convenio IS NULL 
                   OR h.id_convenio = p_id_convenio 
                   OR h.id_convenio IS NULL
               )
               AND (
                   h.id_tipo_aseguramiento = p_id_tipo_aseguramiento 
                   OR h.id_tipo_aseguramiento IS NULL
               )
               AND (
                   CASE 
                       -- Nivel 1: Horario por Día (fecha exacta de inicio y fin)
                       WHEN p_tipo_vigencia = 'POR_DIA' 
                            AND TRUNC(h.fecha_inicial) = TRUNC(p_fecha) 
                            AND TRUNC(h.fecha_final)   = TRUNC(p_fecha) 
                       THEN 1
                       -- Nivel 2: Horario Personalizado (rango de fechas delimitado)
                       WHEN p_tipo_vigencia = 'PERSONALIZADO' 
                            AND TRUNC(h.fecha_inicial) <= TRUNC(p_fecha) 
                            AND TRUNC(h.fecha_final)   >= TRUNC(p_fecha)
                            AND TRUNC(h.fecha_inicial) <> TRUNC(h.fecha_final)
                       THEN 1
                       -- Nivel 3: Horario Base (sin fecha final)
                       WHEN p_tipo_vigencia = 'BASE' 
                            AND TRUNC(h.fecha_inicial) <= TRUNC(p_fecha) 
                            AND h.fecha_final IS NULL
                       THEN 1
                       ELSE 0
                   END = 1
               )
             ORDER BY CASE WHEN h.id_convenio = p_id_convenio THEN 1 ELSE 2 END,
                      h.hora_desde ASC;
    BEGIN
        v_dia_semana := f_obtener_dia_semana(p_fecha);
        v_es_domingo := (v_dia_semana = 'DO');
        v_es_festivo := pkgca_tkr_festivos.f_es_festivo(p_fecha, 1);
        v_trabaja_festivos := pkgca_tkr_usuarios.f_trabaja_festivos(p_id_usuario);
        v_bloqueado_ausencia := pkgca_tkr_ausencias_profesional.f_existe_ausencia(p_id_usuario, p_fecha, p_fecha);

        -- Paso 1: Obtener duración según aseguramiento y modalidad enviando JSON
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

        -- Paso 2: Si el día está bloqueado por ausencia programada
        IF v_bloqueado_ausencia THEN
            SELECT JSON_OBJECT('codigo' VALUE 0, 'mensaje' VALUE 'Día no disponible por ausencia programada del profesional', 'fecha' VALUE TO_CHAR(p_fecha, 'YYYY-MM-DD'), 'dia_semana' VALUE v_dia_semana, 'disponible' VALUE 0, 'motivo_bloqueo' VALUE 'AUSENCIA_PROGRAMADA', 'slots' VALUE JSON_ARRAY(), 'bitmap_disponible' VALUE v_bitmap RETURNING CLOB) INTO p_json_salida FROM DUAL;
            RETURN;
        END IF;

        -- Paso 3: Determinar nivel de horario aplicable respetando jerarquía
        -- Nivel 1: Horario por Día
        SELECT COUNT(1)
          INTO v_total_slots
          FROM tkr_horarios_profesional h
         WHERE h.id_usuario = p_id_usuario
           AND h.dia_semana = v_dia_semana
           AND h.activo = 1
           AND TRUNC(h.fecha_inicial) = TRUNC(p_fecha)
           AND TRUNC(h.fecha_final)   = TRUNC(p_fecha);

        IF v_total_slots > 0 THEN
            v_tipo_horario_aplica := 'POR_DIA';
        ELSE
            -- Si es domingo o festivo y no trabaja festivos (y no tiene Horario por Día excepcional)
            IF (v_es_domingo OR v_es_festivo) AND v_trabaja_festivos = 'N' THEN
                SELECT JSON_OBJECT('codigo' VALUE 0, 'mensaje' VALUE 'Profesional no labora domingos ni festivos', 'fecha' VALUE TO_CHAR(p_fecha, 'YYYY-MM-DD'), 'dia_semana' VALUE v_dia_semana, 'disponible' VALUE 0, 'motivo_bloqueo' VALUE 'FESTIVO_NO_LABORAL', 'slots' VALUE JSON_ARRAY(), 'bitmap_disponible' VALUE v_bitmap RETURNING CLOB) INTO p_json_salida FROM DUAL;
                RETURN;
            END IF;

            -- Nivel 2: Horario Personalizado por rango
            SELECT COUNT(1)
              INTO v_total_slots
              FROM tkr_horarios_profesional h
             WHERE h.id_usuario = p_id_usuario
               AND h.dia_semana = v_dia_semana
               AND h.activo = 1
               AND TRUNC(h.fecha_inicial) <= TRUNC(p_fecha)
               AND TRUNC(h.fecha_final)   >= TRUNC(p_fecha)
               AND TRUNC(h.fecha_inicial) <> TRUNC(h.fecha_final);

            IF v_total_slots > 0 THEN
                v_tipo_horario_aplica := 'PERSONALIZADO';
            ELSE
                -- Nivel 3: Horario Base permanente
                SELECT COUNT(1)
                  INTO v_total_slots
                  FROM tkr_horarios_profesional h
                 WHERE h.id_usuario = p_id_usuario
                   AND h.dia_semana = v_dia_semana
                   AND h.activo = 1
                   AND TRUNC(h.fecha_inicial) <= TRUNC(p_fecha)
                   AND h.fecha_final IS NULL;

                IF v_total_slots > 0 THEN
                    v_tipo_horario_aplica := 'BASE';
                ELSE
                    v_tipo_horario_aplica := 'NINGUNO';
                END IF;
            END IF;
        END IF;

        IF v_tipo_horario_aplica = 'NINGUNO' THEN
            SELECT JSON_OBJECT('codigo' VALUE 0, 'mensaje' VALUE 'Sin programación de horario para esta fecha', 'fecha' VALUE TO_CHAR(p_fecha, 'YYYY-MM-DD'), 'dia_semana' VALUE v_dia_semana, 'disponible' VALUE 0, 'motivo_bloqueo' VALUE 'SIN_HORARIO', 'slots' VALUE JSON_ARRAY(), 'bitmap_disponible' VALUE v_bitmap RETURNING CLOB) INTO p_json_salida FROM DUAL;
            RETURN;
        END IF;

        -- Paso 4: Consultar si existen slots ocupados / citas reservadas en tkr_disponibilidad_bitmap
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

            -- Generar slots e intervalos discretos según los turnos resueltos descontando ocupados
            v_total_slots := 0;
            FOR r_turno IN c_turnos(v_tipo_horario_aplica) LOOP
                DECLARE
                    v_min_inicio NUMBER := f_hora_a_minutos(r_turno.hora_desde);
                    v_min_fin    NUMBER := f_hora_a_minutos(r_turno.hora_hasta);
                    v_actual     NUMBER := v_min_inicio;
                    v_slot_fin   NUMBER;
                    v_idx_inicio NUMBER;
                    v_idx_fin    NUMBER;
                    v_ocupado    BOOLEAN;
                BEGIN
                    WHILE (v_actual + v_duracion_min) <= v_min_fin LOOP
                        v_slot_fin := v_actual + v_duracion_min;
                        v_idx_inicio := TRUNC(v_actual / 5) + 1;
                        v_idx_fin    := TRUNC(v_slot_fin / 5);

                        -- Validar si alguno de los bits del intervalo está marcado como ocupado ('1')
                        v_ocupado := FALSE;
                        FOR i IN v_idx_inicio..v_idx_fin LOOP
                            IF i BETWEEN 1 AND 288 THEN
                                IF SUBSTR(v_bitmap_ocupado_db, i, 1) = '1' THEN
                                    v_ocupado := TRUE;
                                    EXIT;
                                END IF;
                            END IF;
                        END LOOP;

                        -- Solo se agrega a la lista de disponibles si NO está ocupado
                        IF NOT v_ocupado THEN
                            v_slot_obj := JSON_OBJECT_T();
                            v_slot_obj.put('hora_inicio', f_minutos_a_hora(v_actual));
                            v_slot_obj.put('hora_fin', f_minutos_a_hora(v_slot_fin));
                            v_slot_obj.put('duracion_minutos', v_duracion_min);
                            v_slot_obj.put('id_horario', r_turno.id);
                            v_slot_obj.put('id_convenio', r_turno.id_convenio);
                            v_slot_obj.put('disponible', 1);
                            v_slots_arr.append(v_slot_obj);

                            -- Marcar bits en el vector de bitmap disponible
                            FOR i IN v_idx_inicio..v_idx_fin LOOP
                                IF i BETWEEN 1 AND 288 THEN
                                    v_bitmap := SUBSTR(v_bitmap, 1, i - 1) || '1' || SUBSTR(v_bitmap, i + 1);
                                END IF;
                            END LOOP;

                            v_total_slots := v_total_slots + 1;
                        END IF;

                        v_actual := v_slot_fin;
                    END LOOP;
                END;
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
    END p_consultar_slots_dia_json;

    -- 3. Consultar disponibilidad semanal de un profesional (7 días consecutivos)
    PROCEDURE p_consultar_slots_semana_json (
        p_id_usuario            IN  NUMBER,
        p_fecha_inicio          IN  DATE,
        p_id_convenio           IN  NUMBER   DEFAULT NULL,
        p_id_tipo_aseguramiento IN  NUMBER   DEFAULT 1,
        p_modalidad             IN  VARCHAR2 DEFAULT 'V',
        p_json_salida           OUT CLOB
    ) IS
        v_dias_arr JSON_ARRAY_T := JSON_ARRAY_T();
        v_json_dia CLOB;
        v_fecha_actual DATE := TRUNC(p_fecha_inicio);
    BEGIN
        FOR i IN 0..6 LOOP
            p_consultar_slots_dia_json(
                p_id_usuario            => p_id_usuario,
                p_fecha                 => v_fecha_actual + i,
                p_id_convenio           => p_id_convenio,
                p_id_tipo_aseguramiento => p_id_tipo_aseguramiento,
                p_modalidad             => p_modalidad,
                p_json_salida           => v_json_dia
            );
            v_dias_arr.append(JSON_ELEMENT_T.parse(v_json_dia));
        END LOOP;

        DECLARE
            v_sem_obj JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
            v_sem_obj.put('codigo', 0);
            v_sem_obj.put('mensaje', 'Disponibilidad semanal recuperada exitosamente');
            v_sem_obj.put('id_usuario', p_id_usuario);
            v_sem_obj.put('fecha_inicio', TO_CHAR(v_fecha_actual, 'YYYY-MM-DD'));
            v_sem_obj.put('fecha_fin', TO_CHAR(v_fecha_actual + 6, 'YYYY-MM-DD'));
            v_sem_obj.put('semana', v_dias_arr);
            p_json_salida := v_sem_obj.to_clob();
        END;
    END p_consultar_slots_semana_json;

    -- 4. Consultar catálogos para filtros del directorio (especialidades, convenios, aseguramientos)
    PROCEDURE p_consultar_filtros_catalogo_json (
        p_json_salida OUT CLOB
    ) IS
        v_json_especialidades CLOB;
        v_json_convenios      CLOB;
        v_json_aseguramientos CLOB;
    BEGIN
        -- Especialidades activas
        SELECT COALESCE(
                   JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'id'     VALUE e.id,
                           'nombre' VALUE e.nombre_especialidad
                       )
                       ORDER BY e.nombre_especialidad ASC
                       RETURNING CLOB
                   ),
                   TO_CLOB('[]')
               )
          INTO v_json_especialidades
          FROM tkr_especialidades e;

        -- Convenios activos
        SELECT COALESCE(
                   JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'id'     VALUE c.id,
                           'nombre' VALUE c.nombre_convenio
                       )
                       ORDER BY c.nombre_convenio ASC
                       RETURNING CLOB
                   ),
                   TO_CLOB('[]')
               )
          INTO v_json_convenios
          FROM tkr_convenios c
         WHERE c.estado = 'A';

        -- Tipos de aseguramiento
        SELECT COALESCE(
                   JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'id'     VALUE t.id,
                           'nombre' VALUE t.tipo_aseguramiento
                       )
                       ORDER BY t.id ASC
                       RETURNING CLOB
                   ),
                   TO_CLOB('[]')
               )
          INTO v_json_aseguramientos
          FROM tkr_tipos_aseguramiento t;

        SELECT JSON_OBJECT(
                   'codigo'              VALUE 0,
                   'mensaje'             VALUE 'Catálogos consultados exitosamente',
                   'especialidades'      VALUE JSON_QUERY(v_json_especialidades, '$' RETURNING CLOB),
                   'convenios'           VALUE JSON_QUERY(v_json_convenios, '$' RETURNING CLOB),
                   'tipos_aseguramiento' VALUE JSON_QUERY(v_json_aseguramientos, '$' RETURNING CLOB),
                   'modalidades'         VALUE JSON_ARRAY(
                                                   JSON_OBJECT('codigo' VALUE 'V', 'nombre' VALUE 'Virtual'),
                                                   JSON_OBJECT('codigo' VALUE 'D', 'nombre' VALUE 'Domiciliaria')
                                               )
                   RETURNING CLOB
               )
          INTO p_json_salida
          FROM DUAL;
    END p_consultar_filtros_catalogo_json;

    -- 5. Consultar únicamente los intervalos disponibles de un día en formato 12h AM/PM
    -- Retorna: [{"INTERVALO":"08:20 PM"},{"INTERVALO":"08:40 PM"},...]
    PROCEDURE p_consultar_intervalos_dia_json (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_id_usuario            NUMBER;
        v_fecha_str             VARCHAR2(20);
        v_fecha                 DATE;
        v_aseg_letra            VARCHAR2(5);
        v_mod_letra             VARCHAR2(5);
        v_id_tipo_aseguramiento NUMBER := 1; -- 1 = Voluntario por defecto
        v_modalidad             VARCHAR2(1) := 'V'; -- 'V' = Virtual por defecto
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

        -- Extraer parámetros del JSON
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

        -- Regla 2: Tipo de aseguramiento: (V)oluntario = 1 por defecto, (O)bligatorio = 2
        IF v_aseg_letra = 'O' THEN
            v_id_tipo_aseguramiento := 2;
        ELSE
            v_id_tipo_aseguramiento := 1;
        END IF;

        -- Regla 2: Clase de atención: (V)irtual por defecto, (D)omiciliario
        IF v_mod_letra = 'D' THEN
            v_modalidad := 'D';
        ELSE
            v_modalidad := 'V';
        END IF;

        -- Ejecutar la lógica de disponibilidad del día reutilizando el motor
        p_consultar_slots_dia_json(
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
                
                -- Convertir de HH24:MI (ej. 20:20) a HH12:MI AM/PM (ej. 08:20 PM)
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
    END p_consultar_intervalos_dia_json;

    -- 6. Consultar intervalos disponibles en un rango de fechas con formato dd/mm/yyyy
    -- Retorna: [{"fecha":"27/10/2026","intervalos":[{"INTERVALO":"08:20 PM"},...]},...]
    PROCEDURE p_consultar_intervalos_rango_json (
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
        v_id_tipo_aseguramiento NUMBER := 1; -- 1 = Voluntario por defecto
        v_modalidad             VARCHAR2(1) := 'V'; -- 'V' = Virtual por defecto
        v_id_convenio           NUMBER;
        v_solo_disp_str         VARCHAR2(5);
        v_solo_disp             BOOLEAN := TRUE; -- Por defecto filtra solo días con disponibilidad

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

        -- Extraer parámetros del JSON
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

        -- Conversión de fecha inicial (admite YYYY-MM-DD o DD/MM/YYYY)
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

        -- Conversión de fecha final
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

        -- Validar orden de fechas
        IF v_fecha_fin < v_fecha_inicio THEN
            DECLARE
                v_tmp DATE := v_fecha_inicio;
            BEGIN
                v_fecha_inicio := v_fecha_fin;
                v_fecha_fin := v_tmp;
            END;
        END IF;

        -- Proteger contra rangos excesivos (máximo 60 días)
        IF (v_fecha_fin - v_fecha_inicio) > 60 THEN
            v_fecha_fin := v_fecha_inicio + 60;
        END IF;

        -- Regla 2: Tipo de aseguramiento: (V)oluntario = 1 por defecto, (O)bligatorio = 2
        IF v_aseg_letra = 'O' THEN
            v_id_tipo_aseguramiento := 2;
        ELSE
            v_id_tipo_aseguramiento := 1;
        END IF;

        -- Regla 2: Clase de atención: (V)irtual por defecto, (D)omiciliario
        IF v_mod_letra = 'D' THEN
            v_modalidad := 'D';
        ELSE
            v_modalidad := 'V';
        END IF;

        -- Filtrado de días: por defecto 'S' (solo días con disponibilidad)
        IF v_solo_disp_str = 'N' THEN
            v_solo_disp := FALSE;
        ELSE
            v_solo_disp := TRUE;
        END IF;

        -- Recorrer el rango de fechas día a día
        v_fecha_cur := TRUNC(v_fecha_inicio);
        WHILE v_fecha_cur <= TRUNC(v_fecha_fin) LOOP
            v_intervalos_arr := JSON_ARRAY_T();

            p_consultar_slots_dia_json(
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

            -- Si no es modo estricto o si tiene al menos un intervalo disponible, se incluye el día
            IF NOT v_solo_disp OR v_intervalos_arr.get_size > 0 THEN
                v_dia_obj := JSON_OBJECT_T();
                -- Formato dd/mm/yyyy solicitado
                v_dia_obj.put('fecha', TO_CHAR(v_fecha_cur, 'DD/MM/YYYY'));
                v_dia_obj.put('intervalos', v_intervalos_arr);
                v_resultado_arr.append(v_dia_obj);
            END IF;

            v_fecha_cur := v_fecha_cur + 1;
        END LOOP;

        p_json_salida := v_resultado_arr.to_clob();
    END p_consultar_intervalos_rango_json;

END pkgcn_directorio_profesionales;
/

