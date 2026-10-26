CREATE OR REPLACE PACKAGE pkgca_tkr_tiempos_atencion
AS
    /*
          Nombre       : pkgca_tkr_tiempos_atencion
          Descripción  : Paquete de Acceso No-PK y operaciones mono-tabla sobre 
                         la tabla tkr_tiempos_atencion.
          Autor        : Orlando Arturo Valverde Quiceno
          e-mail       : vqorlando@gmail.com
          ----------------------------------------------------------------------
          Control de modificaciones
          Fecha        Efectuadas por                     Descripción
          ----------   ---------------   ---------------------------------------
          26/10/2026   OAVQ              1. Creación inicial
          26/10/2026   OAVQ              2. Adaptación a parámetro JSON de entrada
                                            evaluado con JSON_VALUE
    */

    /*
          Nombre       : f_obtener_duracion_cita
          Descripción  : Función para consultar la duración en minutos configurada 
                         para un profesional según el tipo de aseguramiento y la 
                         modalidad de atención.
                         Recibe un payload JSON con las claves:
                         - id_usuario (NUMBER)
                         - id_tipo_aseguramiento (NUMBER)
                         - modalidad (VARCHAR2: 'V' / 'D')
                         Si no existe registro configurado o el valor es inválido, 
                         retorna el valor por defecto institucional (20 min).
          -----------------------------------------------------------------------
          Control de modificaciones
          Fecha        Efectuadas por                     Descripción
          ----------   ---------------   ----------------------------------------
          26/10/2026   OAVQ              1. Creación
          26/10/2026   OAVQ              2. Parámetro p_json_entrada CLOB
    */
    FUNCTION f_obtener_duracion_cita (
        p_json_entrada IN CLOB
    ) RETURN NUMBER;

    /*
          Nombre       : f_consultar_x_profesional
          Descripción  : Función que retorna un cursor con todas las configuraciones 
                         de tiempos de atención activas para un profesional.
                         Recibe un payload JSON con la clave:
                         - id_usuario (NUMBER)
          -----------------------------------------------------------------------
          Control de modificaciones
          Fecha        Efectuadas por                     Descripción
          ----------   ---------------   ----------------------------------------
          26/10/2026   OAVQ              1. Creación
          26/10/2026   OAVQ              2. Parámetro p_json_entrada CLOB
    */
    FUNCTION f_consultar_x_profesional (
        p_json_entrada IN CLOB
    ) RETURN SYS_REFCURSOR;

END pkgca_tkr_tiempos_atencion;
/
