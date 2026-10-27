'use client';

import React, { useState, useEffect, useCallback, useMemo } from 'react';
import {
  Search,
  Calendar,
  Clock,
  MapPin,
  Video,
  Stethoscope,
  ChevronLeft,
  ChevronRight,
  X,
  AlertCircle,
  Copy,
  Check,
  Terminal,
  Code2,
  PhoneCall,
  Star,
  Award,
  Sparkles
} from 'lucide-react';

interface SpecialtyItem {
  id: number;
  nombre_especialidad: string;
  tipo_especialidad?: string;
}

interface Profesional {
  id: number;
  id_usuario?: number;
  fullName: string;
  nombre_completo?: string;
  nombres?: string;
  apellidos?: string;
  correo?: string;
  telefono?: string;
  trabaja_festivos: string;
  slug?: string;
  gender?: string | null;
  rate?: number | null;
  reviews?: number;
  specialty?: SpecialtyItem[];
  especialidades?: { id: number; nombre: string }[];
  esp_subesp?: string;
  subspecialty?: string | null;
  img_url?: string | null;
  url_foto?: string | null;
  specialtiesIds?: string;
  modalidades?: string[];
  days_of_service?: string[] | string | null;
}

interface FiltrosCatalogo {
  especialidades: { id: number; nombre: string }[];
  convenios: { id: number; nombre: string }[];
  tipos_aseguramiento: { id: number; nombre: string }[];
  modalidades: { codigo: string; nombre: string }[];
}

interface SlotItem {
  hora_inicio: string;
  hora_fin: string;
  duracion_minutos: number;
  id_horario?: number;
  id_convenio?: number;
  disponible: number;
}

interface DiaRangoItem {
  fecha: string;
  diaNombre: string;
  diaNum: string;
  mesNombre: string;
}

// Helper defensivo para garantizar arreglos válidos incluso si Oracle devuelve cadenas JSON o CLOBs
function normalizarArreglo<T>(valor: any): T[] {
  if (!valor) return [];
  if (Array.isArray(valor)) return valor;
  if (typeof valor === 'string') {
    const trimmed = valor.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        const parsed = JSON.parse(trimmed);
        return Array.isArray(parsed) ? parsed : [];
      } catch {
        return [];
      }
    }
  }
  return [];
}

export default function DirectorioPage() {
  // Estado de catálogos
  const [catalogos, setCatalogos] = useState<FiltrosCatalogo>({
    especialidades: [],
    convenios: [],
    tipos_aseguramiento: [],
    modalidades: []
  });

  // Filtros activos
  const [busqueda, setBusqueda] = useState('');
  const [idEspecialidad, setIdEspecialidad] = useState<number | ''>('');
  const [idConvenio, setIdConvenio] = useState<number | ''>('');
  const [idTipoAseguramiento, setIdTipoAseguramiento] = useState<number>(1); // 1 = Voluntario por defecto
  const [modalidad, setModalidad] = useState<string>(''); // '' = Todas
  const [pagina, setPagina] = useState(1);

  // Rango de fechas de consulta
  const [fechaInicio, setFechaInicio] = useState<string>(() => {
    const d = new Date();
    return d.toISOString().split('T')[0];
  });
  const [fechaFin, setFechaFin] = useState<string>(() => {
    const d = new Date();
    d.setDate(d.getDate() + 6);
    return d.toISOString().split('T')[0];
  });

  // Datos del directorio
  const [profesionales, setProfesionales] = useState<Profesional[]>([]);
  const [totalRegistros, setTotalRegistros] = useState(0);
  const [totalPaginas, setTotalPaginas] = useState(1);
  const [cargando, setCargando] = useState(false);

  // Modal de disponibilidad
  const [medicoSeleccionado, setMedicoSeleccionado] = useState<Profesional | null>(null);
  const [diaSeleccionadoModal, setDiaSeleccionadoModal] = useState<string>('');
  const [diasDisponiblesModal, setDiasDisponiblesModal] = useState<DiaRangoItem[]>([]);
  const [totalSlotsRangoModal, setTotalSlotsRangoModal] = useState<number | null>(null);
  const [diasMapModal, setDiasMapModal] = useState<Record<string, {
    slots: SlotItem[];
    tipo_horario_aplica: string;
    duracion_cita_min: number;
    mensaje: string;
    disponible?: number;
  }>>({});
  const [slotsData, setSlotsData] = useState<{
    slots: SlotItem[];
    tipo_horario_aplica: string;
    duracion_cita_min: number;
    mensaje: string;
    disponible?: number;
  } | null>(null);
  const [cargandoSlots, setCargandoSlots] = useState(false);
  const [slotSeleccionado, setSlotSeleccionado] = useState<SlotItem | null>(null);

  // Modal de depuración PL/SQL (Ctrl + Alt + D)
  const [mostrarModalDebug, setMostrarModalDebug] = useState(false);
  const [copiado, setCopiado] = useState(false);


  // Calcular arreglo de días dentro del rango [fechaInicio .. fechaFin]
  const diasRango = useMemo<DiaRangoItem[]>(() => {
    const lista: DiaRangoItem[] = [];
    if (!fechaInicio || !fechaFin) return lista;

    const [y1, m1, d1] = fechaInicio.split('-').map(Number);
    const [y2, m2, d2] = fechaFin.split('-').map(Number);
    const fInicio = new Date(y1, m1 - 1, d1);
    const fFin = new Date(y2, m2 - 1, d2);

    if (fInicio > fFin) return lista;

    const nombresDias = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
    const nombresMeses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

    const actual = new Date(fInicio);
    let contador = 0;
    while (actual <= fFin && contador < 365) {
      // Limitar a 365 días máximo por seguridad
      const y = actual.getFullYear();
      const m = String(actual.getMonth() + 1).padStart(2, '0');
      const d = String(actual.getDate()).padStart(2, '0');
      const iso = `${y}-${m}-${d}`;

      lista.push({
        fecha: iso,
        diaNombre: nombresDias[actual.getDay()],
        diaNum: String(actual.getDate()),
        mesNombre: nombresMeses[actual.getMonth()]
      });

      actual.setDate(actual.getDate() + 1);
      contador++;
    }
    return lista;
  }, [fechaInicio, fechaFin]);

  // Listener para atajo de teclado Ctrl + Alt + D
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.ctrlKey && e.altKey && (e.key === 'd' || e.key === 'D')) {
        e.preventDefault();
        setMostrarModalDebug((prev) => !prev);
      }
      if (e.key === 'Escape') {
        setMostrarModalDebug(false);
      }
    }
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  // Cargar catálogos iniciales
  useEffect(() => {
    async function cargarFiltros() {
      try {
        const res = await fetch('/api/filtros');
        const data = await res.json();
        if (data && data.codigo === 0) {
          setCatalogos({
            especialidades: data.especialidades || [],
            convenios: data.convenios || [],
            tipos_aseguramiento: data.tipos_aseguramiento || [],
            modalidades: data.modalidades || []
          });
        }
      } catch (err) {
        console.error('Error al cargar filtros:', err);
      }
    }
    cargarFiltros();
  }, []);

  // Consultar profesionales con debounce
  const cargarDirectorio = useCallback(async () => {
    setCargando(true);
    try {
      const payload: any = {
        pagina,
        registros_por_pagina: 12,
        busqueda: busqueda.trim() || null,
        id_tipo_aseguramiento: idTipoAseguramiento || null,
        id_especialidad: idEspecialidad || null,
        id_convenio: idConvenio || null,
        modalidad: modalidad || null,
        fecha_inicio: fechaInicio,
        fecha_fin: fechaFin
      };

      const res = await fetch('/api/directorio', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const data = await res.json();

      if (data && data.codigo === 0) {
        setProfesionales(data.profesionales || []);
        setTotalRegistros(data.total_registros || 0);
        setTotalPaginas(data.total_paginas || 1);
      } else {
        setProfesionales([]);
        setTotalRegistros(0);
      }
    } catch (err) {
      console.error('Error consultando directorio:', err);
      setProfesionales([]);
    } finally {
      setCargando(false);
    }
  }, [pagina, busqueda, idEspecialidad, idConvenio, idTipoAseguramiento, modalidad, fechaInicio, fechaFin]);

  useEffect(() => {
    const timer = setTimeout(() => {
      cargarDirectorio();
    }, 250);
    return () => clearTimeout(timer);
  }, [cargarDirectorio]);

  // Consultar slots de un médico para una fecha específica
  const cargarSlotsDia = useCallback(
    async (idUsuario: number, fecha: string) => {
      setCargandoSlots(true);
      setSlotSeleccionado(null);
      try {
        const payload = {
          id_usuario: idUsuario,
          fecha,
          tipo_vista: 'DIA',
          id_convenio: idConvenio || null,
          id_tipo_aseguramiento: idTipoAseguramiento || 1,
          modalidad: modalidad || 'V'
        };

        const res = await fetch('/api/disponibilidad', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        const data = await res.json();

        if (data && data.codigo === 0) {
          setSlotsData({
            slots: data.slots || [],
            tipo_horario_aplica: data.tipo_horario_aplica || 'NINGUNO',
            duracion_cita_min: data.duracion_cita_min || 20,
            mensaje: data.mensaje || '',
            disponible: data.disponible !== undefined ? data.disponible : 1
          });
        } else {
          setSlotsData({
            slots: [],
            tipo_horario_aplica: 'NINGUNO',
            duracion_cita_min: 20,
            mensaje: data.mensaje || 'Sin disponibilidad programada',
            disponible: 0
          });
        }
      } catch (err: any) {
        console.error('Error consultando disponibilidad:', err);
        setSlotsData({
          slots: [],
          tipo_horario_aplica: 'ERROR',
          duracion_cita_min: 20,
          mensaje: err.message || 'Error de conexión con la base de datos',
          disponible: 0
        });
      } finally {
        setCargandoSlots(false);
      }
    },
    [idConvenio, idTipoAseguramiento, modalidad]
  );

  // Abrir modal de un médico seleccionado
  async function abrirDisponibilidad(medico: Profesional) {
    setMedicoSeleccionado(medico);
    setCargandoSlots(true);
    setSlotSeleccionado(null);
    setSlotsData(null);
    setDiasDisponiblesModal([]);
    setDiasMapModal({});
    setTotalSlotsRangoModal(null);

    const fIni = fechaInicio || new Date().toISOString().split('T')[0];
    const fFin = fechaFin || fIni;
    const idProf = medico.id || medico.id_usuario || 0;

    try {
      // 1. Consultar el rango completo para traer de una vez todos los días y sus intervalos
      const payloadRango = {
        id_usuario: idProf,
        tipo_vista: 'RANGO',
        fecha_inicio: fIni,
        fecha_fin: fFin,
        id_convenio: idConvenio || null,
        id_tipo_aseguramiento: idTipoAseguramiento || 1,
        modalidad: modalidad || 'V'
      };

      const res = await fetch('/api/disponibilidad', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payloadRango)
      });
      const data = await res.json();

      if (data && data.codigo === 0) {
        const totalSlots = data.total_slots_rango || 0;
        setTotalSlotsRangoModal(totalSlots);

        // Construir mapa indexado por fecha con todos los intervalos en memoria
        const mapaSlots: Record<string, {
          slots: SlotItem[];
          tipo_horario_aplica: string;
          duracion_cita_min: number;
          mensaje: string;
          disponible?: number;
        }> = {};

        (data.dias_disponibles || []).forEach((d: any) => {
          mapaSlots[d.fecha] = {
            slots: d.slots || [],
            tipo_horario_aplica: d.tipo_horario_aplica || 'NINGUNO',
            duracion_cita_min: d.duracion_cita_min || 20,
            mensaje: d.mensaje || '',
            disponible: d.disponible !== undefined ? d.disponible : 1
          };
        });

        setDiasMapModal(mapaSlots);

        // Mapear días con turnos disponibles a formato DiaRangoItem
        const nombresDias = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
        const nombresMeses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

        const diasValidos: DiaRangoItem[] = (data.dias_disponibles || []).map((d: any) => {
          const [yy, mm, dd] = d.fecha.split('-').map(Number);
          const fObj = new Date(yy, mm - 1, dd);
          return {
            fecha: d.fecha,
            diaNombre: nombresDias[fObj.getDay()],
            diaNum: String(dd),
            mesNombre: nombresMeses[mm - 1]
          };
        });

        setDiasDisponiblesModal(diasValidos);

        // Si tiene días con disponibilidad, auto-seleccionar el primero y cargar sus slots al instante
        if (diasValidos.length > 0) {
          const primerDia = diasValidos[0].fecha;
          setDiaSeleccionadoModal(primerDia);

          if (mapaSlots[primerDia]) {
            setSlotsData(mapaSlots[primerDia]);
          } else {
            cargarSlotsDia(idProf, primerDia);
          }
        } else {
          // No tiene intervalos en todo el rango
          setDiaSeleccionadoModal('');
          setSlotsData({
            slots: [],
            tipo_horario_aplica: 'NINGUNO',
            duracion_cita_min: 20,
            mensaje: 'Sin disponibilidad en el rango seleccionado',
            disponible: 0
          });
        }
      } else {
        setTotalSlotsRangoModal(0);
        setDiasDisponiblesModal([]);
        setDiasMapModal({});
      }
    } catch (err: any) {
      console.error('Error consultando disponibilidad en rango:', err);
      setTotalSlotsRangoModal(0);
      setDiasDisponiblesModal([]);
      setDiasMapModal({});
    } finally {
      setCargandoSlots(false);
    }
  }

  // Cambiar el día seleccionado en el modal (instantáneo desde la memoria previa)
  function seleccionarDiaModal(fecha: string) {
    if (!medicoSeleccionado) return;
    setDiaSeleccionadoModal(fecha);
    setSlotSeleccionado(null);

    // Si ya tenemos los intervalos en memoria para esta fecha, cargarlos sin ninguna demora de red
    if (diasMapModal[fecha]) {
      setSlotsData(diasMapModal[fecha]);
    } else {
      cargarSlotsDia(medicoSeleccionado.id || medicoSeleccionado.id_usuario || 0, fecha);
    }
  }


  // Generar bloque anónimo PL/SQL según el contexto activo
  const payloadActual = useMemo(() => {
    if (medicoSeleccionado) {
      return {
        procedimiento: 'PKGLN_DIRECTORIO_PROFESIONALES.p_consultar_disponibilidad',
        descripcion:
          'Consulta la disponibilidad horaria, jerarquía de turnos y vector bitmap (288 posiciones de 5 min) de un profesional específico para un día o semana.',
        jsonEntrada: {
          id_usuario: medicoSeleccionado.id || medicoSeleccionado.id_usuario || 0,
          fecha: diaSeleccionadoModal || fechaInicio,
          tipo_vista: 'DIA',
          id_convenio: idConvenio || null,
          id_tipo_aseguramiento: idTipoAseguramiento || 1,
          modalidad: modalidad || 'V'
        },
        parametrosDoc: [
          {
            campo: 'id_usuario',
            tipo: 'NUMBER(12)',
            obligatorio: 'SÍ',
            descripcion: 'Identificador único del profesional médico (FK a tkr_usuarios.id)',
            ejemplo: String(medicoSeleccionado.id_usuario)
          },
          {
            campo: 'fecha',
            tipo: 'VARCHAR2(10)',
            obligatorio: 'SÍ',
            descripcion: 'Fecha a consultar en formato obligatorio ISO YYYY-MM-DD',
            ejemplo: diaSeleccionadoModal || fechaInicio
          },
          {
            campo: 'tipo_vista',
            tipo: 'VARCHAR2(10)',
            obligatorio: 'NO',
            descripcion: "'DIA' para cálculo de slots por bloques de tiempo o 'SEMANA' para 7 días continuos",
            ejemplo: "'DIA'"
          },
          {
            campo: 'id_convenio',
            tipo: 'NUMBER(12)',
            obligatorio: 'NO',
            descripcion: 'ID del convenio (tkr_convenios.id). NULL evalúa turnos generales y todos los convenios',
            ejemplo: idConvenio ? String(idConvenio) : 'NULL'
          },
          {
            campo: 'id_tipo_aseguramiento',
            tipo: 'NUMBER(12)',
            obligatorio: 'SÍ',
            descripcion: '1 = Voluntario (Prepagada/Póliza), 2 = Obligatorio (EPS). Regla de Negocio: Si una franja no tiene marcado tipo de aseguramiento (NULL en tkr_horarios_profesional), APLICA PARA TODOS los tipos de aseguramiento.',
            ejemplo: String(idTipoAseguramiento)
          },
          {
            campo: 'modalidad',
            tipo: 'VARCHAR2(1)',
            obligatorio: 'SÍ',
            descripcion: "'V' = Telemedicina / Virtual, 'D' = Atención Médica Domiciliaria",
            ejemplo: `'${modalidad || 'V'}'`
          }
        ],
        salidaDoc: [
          {
            campo: 'codigo',
            tipo: 'NUMBER',
            descripcion: '0 para ejecución exitosa; valor negativo (< 0) para errores de negocio o control'
          },
          {
            campo: 'mensaje',
            tipo: 'VARCHAR2',
            descripcion: "Mensaje descriptivo del resultado ('Disponibilidad recuperada exitosamente', bloqueos, ausencias, etc.)"
          },
          {
            campo: 'id_usuario',
            tipo: 'NUMBER',
            descripcion: 'Identificador del profesional médico evaluado'
          },
          {
            campo: 'fecha',
            tipo: 'VARCHAR2(10)',
            descripcion: 'Fecha consultada en formato YYYY-MM-DD'
          },
          {
            campo: 'dia_semana',
            tipo: 'VARCHAR2(2)',
            descripcion: "Código del día de la semana calculado ('LU', 'MA', 'MI', 'JU', 'VI', 'SA', 'DO')"
          },
          {
            campo: 'tipo_horario_aplica',
            tipo: 'VARCHAR2',
            descripcion: "Jerarquía de turno aplicada: 'POR_DIA' (Prio 1), 'PERSONALIZADO' (Prio 2), 'BASE' (Prio 3) o 'NINGUNO'"
          },
          {
            campo: 'duracion_cita_min',
            tipo: 'NUMBER',
            descripcion: 'Duración en minutos de cada cita según tkr_tiempos_atencion, modalidad y tipo de aseguramiento'
          },
          {
            campo: 'total_slots',
            tipo: 'NUMBER',
            descripcion: 'Número total de intervalos de cita calculados y disponibles para la fecha'
          },
          {
            campo: 'bitmap_disponible',
            tipo: 'VARCHAR2(288)',
            descripcion: 'Cadena binaria de 288 caracteres (1 bit = 5 minutos desde 00:00 a 23:55). 1 = Disponible, 0 = No disponible'
          },
          {
            campo: 'slots',
            tipo: 'JSON_ARRAY',
            descripcion: "Arreglo de intervalos discretos [{ hora_inicio: 'HH24:MI', hora_fin: 'HH24:MI', duracion_minutos, id_horario, id_convenio, disponible: 1 }]"
          }
        ],
        ejemploSalidaJson: JSON.stringify(
          {
            codigo: 0,
            mensaje: 'Disponibilidad recuperada exitosamente',
            id_usuario: medicoSeleccionado.id_usuario,
            fecha: diaSeleccionadoModal || fechaInicio,
            dia_semana: 'LU',
            tipo_horario_aplica: 'BASE',
            duracion_cita_min: 20,
            total_slots: 2,
            bitmap_disponible: '00000000...11110000...',
            slots: [
              {
                hora_inicio: '08:00',
                hora_fin: '08:20',
                duracion_minutos: 20,
                id_horario: 101,
                id_convenio: null,
                disponible: 1
              },
              {
                hora_inicio: '08:20',
                hora_fin: '08:40',
                duracion_minutos: 20,
                id_horario: 101,
                id_convenio: null,
                disponible: 1
              }
            ]
          },
          null,
          2
        ),
        reglasNegocio: [
          'Jerarquía de Horarios: Nivel 1 (Horario por Día: fecha_inicial = fecha_final = fecha) prevalece sobre Nivel 2 (Personalizado: fecha_inicial <= fecha <= fecha_final), y éste sobre Nivel 3 (Base permanente: fecha_final IS NULL).',
          'Tipo de Aseguramiento: Si una franja de horario NO tiene asignado tipo de aseguramiento (id_tipo_aseguramiento IS NULL en tkr_horarios_profesional), APLICA UNIVERSALMENTE para todos los tipos de aseguramiento (Voluntario y Obligatorio).',
          'Convenios: Si id_convenio IS NULL en la franja, aplica a consultas generales y a cualquier convenio.',
          'Ausencias y Festivos: Las ausencias programadas (tkr_ausencias_profesional) bloquean la fecha completa devolviendo total_slots: 0 y motivo_bloqueo: AUSENCIA_PROGRAMADA. Festivos y domingos se bloquean salvo que el profesional tenga trabaja_festivos = S o cuente con un Horario por Día explícito.'
        ]
      };
    }

    return {
      procedimiento: 'PKGLN_DIRECTORIO_PROFESIONALES.p_consultar_directorio',
      descripcion:
        'Consulta el directorio paginado de profesionales habilitados (id_estado_usuario = 1, id_rol = 4 o roles_usuario y franja horaria activa) con filtros multidimensionales.',
      jsonEntrada: {
        pagina,
        registros_por_pagina: 12,
        busqueda: busqueda.trim() || null,
        id_especialidad: idEspecialidad || null,
        id_convenio: idConvenio || null,
        id_tipo_aseguramiento: idTipoAseguramiento || null,
        modalidad: modalidad || null
      },
      parametrosDoc: [
        {
          campo: 'pagina',
          tipo: 'NUMBER',
          obligatorio: 'NO',
          descripcion: 'Número de página a recuperar (1-based, por defecto 1)',
          ejemplo: String(pagina)
        },
        {
          campo: 'registros_por_pagina',
          tipo: 'NUMBER',
          obligatorio: 'NO',
          descripcion: 'Cantidad de profesionales devueltos por página (server-side pagination)',
          ejemplo: '12'
        },
        {
          campo: 'busqueda',
          tipo: 'VARCHAR2',
          obligatorio: 'NO',
          descripcion: 'Texto parcial para búsqueda sobre nombres, apellidos o correo electrónico',
          ejemplo: busqueda ? `'${busqueda}'` : 'NULL'
        },
        {
          campo: 'id_especialidad',
          tipo: 'NUMBER(12)',
          obligatorio: 'NO',
          descripcion: 'Identificador de la especialidad médica (tkr_especialidades.id)',
          ejemplo: idEspecialidad ? String(idEspecialidad) : 'NULL'
        },
        {
          campo: 'id_convenio',
          tipo: 'NUMBER(12)',
          obligatorio: 'NO',
          descripcion: 'Convenio admitido por el profesional en sus horarios (tkr_convenios.id)',
          ejemplo: idConvenio ? String(idConvenio) : 'NULL'
        },
        {
          campo: 'id_tipo_aseguramiento',
          tipo: 'NUMBER(12)',
          obligatorio: 'NO',
          descripcion: '1 = Voluntario, 2 = Obligatorio. Regla de Negocio: Si una franja no tiene aseguramiento marcado (NULL), aplica para todos los tipos.',
          ejemplo: idTipoAseguramiento ? String(idTipoAseguramiento) : 'NULL'
        },
        {
          campo: 'modalidad',
          tipo: 'VARCHAR2(1)',
          obligatorio: 'NO',
          descripcion: "'V' = Virtual, 'D' = Domiciliaria (filtra profesionales con franjas en dicha modalidad)",
          ejemplo: modalidad ? `'${modalidad}'` : 'NULL'
        }
      ],
      salidaDoc: [
        {
          campo: 'codigo',
          tipo: 'NUMBER',
          descripcion: '0 = Operación exitosa; código negativo en caso de excepción'
        },
        {
          campo: 'mensaje',
          tipo: 'VARCHAR2',
          descripcion: 'Descripción del resultado obtenido'
        },
        {
          campo: 'total_registros',
          tipo: 'NUMBER',
          descripcion: 'Cantidad total de profesionales habilitados que coinciden con los criterios de filtrado'
        },
        {
          campo: 'total_paginas',
          tipo: 'NUMBER',
          descripcion: 'Número total de páginas calculadas según registros_por_pagina'
        },
        {
          campo: 'pagina_actual',
          tipo: 'NUMBER',
          descripcion: 'Índice de la página actual consultada (1-based)'
        },
        {
          campo: 'registros_pagina',
          tipo: 'NUMBER',
          descripcion: 'Límite de registros solicitados por página'
        },
        {
          campo: 'profesionales',
          tipo: 'JSON_ARRAY',
          descripcion:
            'Arreglo de objetos de profesionales habilitados. Cada elemento contiene: id_usuario (NUMBER, ID en tkr_usuarios), nombres (VARCHAR2), apellidos (VARCHAR2), correo (VARCHAR2), telefono (VARCHAR2), trabaja_festivos (VARCHAR2 "S"/"N"), url_foto (VARCHAR2 URL imagen avatar), especialidades (JSON_ARRAY con [{ id, nombre }]), modalidades (JSON_ARRAY con ["V", "D"]).'
        }
      ],
      ejemploSalidaJson: JSON.stringify(
        {
          codigo: 0,
          mensaje: 'Directorio consultado exitosamente',
          total_registros: 1,
          total_paginas: 1,
          pagina_actual: 1,
          registros_pagina: 12,
          profesionales: [
            {
              id_usuario: 65,
              nombres: 'Carlos',
              apellidos: 'Rojas',
              correo: 'carlos.rojas@ejemplo.com',
              telefono: '3001234567',
              trabaja_festivos: 'N',
              url_foto: 'https://tekerapp.maxapex.net/FILES_DEV_TEKER/logo_circulo.png',
              especialidades: [
                { id: 10, nombre: 'Medicina General' },
                { id: 25, nombre: 'Pediatría' }
              ],
              modalidades: ['V', 'D']
            }
          ]
        },
        null,
        2
      ),
      reglasNegocio: [
        'Habilitación: Solo se listan profesionales con id_estado_usuario = 1, rol médico (id_rol = 4 en tkr_usuarios o en tkr_roles_usuario) y con al menos un horario activo registrado (tkr_horarios_profesional.activo = 1).',
        'Tipo de Aseguramiento: Si un horario del médico no especifica tipo de aseguramiento (id_tipo_aseguramiento IS NULL), se considera compatible con cualquier tipo de aseguramiento seleccionado.',
        'Modalidades: Obtenidas a partir de las franjas activas en tkr_franjas_profesional (Virtual y/o Domiciliaria).'
      ]
    };
  }, [
    medicoSeleccionado,
    diaSeleccionadoModal,
    fechaInicio,
    idConvenio,
    idTipoAseguramiento,
    modalidad,
    pagina,
    busqueda,
    idEspecialidad
  ]);

  const codigoPlsqlAnonimo = useMemo(() => {
    const payloadStr = JSON.stringify(payloadActual.jsonEntrada, null, 2);
    return `SET SERVEROUTPUT ON SIZE UNLIMITED;
DECLARE
    v_json_entrada CLOB;
    v_json_salida  CLOB;
BEGIN
    -- Payload de entrada estructurado para el orquestador
    v_json_entrada := '${payloadStr.replace(/'/g, "''")}';

    -- Invocación oficial del orquestador transaccional PKGLN
    ${payloadActual.procedimiento}(
        p_json_entrada => v_json_entrada,
        p_json_salida  => v_json_salida
    );

    DBMS_OUTPUT.PUT_LINE('========================================================');
    DBMS_OUTPUT.PUT_LINE('RESPUESTA JSON RETORNADA POR ${payloadActual.procedimiento}:');
    DBMS_OUTPUT.PUT_LINE('========================================================');
    DBMS_OUTPUT.PUT_LINE(v_json_salida);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR INESPERADO PL/SQL: ' || SQLERRM);
END;
/`;
  }, [payloadActual]);

  function copiarAlPortapapeles() {
    navigator.clipboard.writeText(codigoPlsqlAnonimo);
    setCopiado(true);
    setTimeout(() => setCopiado(false), 2500);
  }

  return (
    <div>
      {/* Header Corporativo */}
      <header className="header">
        <div className="container header-inner">
          <div className="logo-title">
            <span className="logo-badge">TEKER</span>
            <div>
              <h1 style={{ fontSize: '1.25rem', fontWeight: 700 }}>Directorio de Profesionales</h1>
              <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>
                Búsqueda y consulta de disponibilidad horaria en tiempo real
              </p>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
            {/* Rango de Fechas */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <Calendar size={16} style={{ color: 'var(--text-muted)' }} />
              <span style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-muted)' }}>Rango:</span>
              <input
                type="date"
                className="form-control"
                style={{ width: 145 }}
                value={fechaInicio}
                onChange={(e) => setFechaInicio(e.target.value)}
              />
              <span style={{ color: 'var(--text-muted)', fontSize: '0.85rem' }}>a</span>
              <input
                type="date"
                className="form-control"
                style={{ width: 145 }}
                value={fechaFin}
                onChange={(e) => setFechaFin(e.target.value)}
              />
            </div>

            {/* Botón de acceso directo a la consola de depuración PL/SQL */}
            <button
              type="button"
              className="debug-badge"
              title="Atajo de teclado: Ctrl + Alt + D"
              onClick={() => setMostrarModalDebug(true)}
            >
              <Code2 size={15} style={{ color: 'var(--primary)' }} />
              <span>Ctrl+Alt+D (PL/SQL)</span>
            </button>
          </div>
        </div>
      </header>

      <main className="container">
        {/* Tarjeta de Filtros de Búsqueda */}
        <section className="filter-card">
          <div className="filter-grid">
            {/* Buscador de Texto */}
            <div className="form-group" style={{ gridColumn: 'span 2' }}>
              <label className="form-label">Buscar Profesional</label>
              <div style={{ position: 'relative' }}>
                <Search size={18} style={{ position: 'absolute', left: 12, top: 12, color: 'var(--text-muted)' }} />
                <input
                  type="text"
                  className="form-control"
                  style={{ paddingLeft: 38 }}
                  placeholder="Nombre, apellido o correo..."
                  value={busqueda}
                  onChange={(e) => {
                    setBusqueda(e.target.value);
                    setPagina(1);
                  }}
                />
              </div>
            </div>

            {/* Selector de Especialidad */}
            <div className="form-group">
              <label className="form-label">Especialidad</label>
              <select
                className="form-control"
                value={idEspecialidad}
                onChange={(e) => {
                  setIdEspecialidad(e.target.value ? Number(e.target.value) : '');
                  setPagina(1);
                }}
              >
                <option value="">Todas las especialidades</option>
                {catalogos.especialidades.map((esp) => (
                  <option key={esp.id} value={esp.id}>
                    {esp.nombre}
                  </option>
                ))}
              </select>
            </div>

            {/* Selector de Convenio */}
            <div className="form-group">
              <label className="form-label">Convenio / Aseguradora</label>
              <select
                className="form-control"
                value={idConvenio}
                onChange={(e) => {
                  setIdConvenio(e.target.value ? Number(e.target.value) : '');
                  setPagina(1);
                }}
              >
                <option value="">Todos los convenios (General)</option>
                {catalogos.convenios.map((conv) => (
                  <option key={conv.id} value={conv.id}>
                    {conv.nombre}
                  </option>
                ))}
              </select>
            </div>

            {/* Tipo de Aseguramiento */}
            <div className="form-group">
              <label className="form-label">Tipo de Aseguramiento</label>
              <select
                className="form-control"
                value={idTipoAseguramiento}
                onChange={(e) => {
                  setIdTipoAseguramiento(Number(e.target.value));
                  setPagina(1);
                }}
              >
                {catalogos.tipos_aseguramiento.map((aseg) => (
                  <option key={aseg.id} value={aseg.id}>
                    {aseg.nombre}
                  </option>
                ))}
              </select>
            </div>

            {/* Modalidad de Atención */}
            <div className="form-group">
              <label className="form-label">Modalidad</label>
              <select
                className="form-control"
                value={modalidad}
                onChange={(e) => {
                  setModalidad(e.target.value);
                  setPagina(1);
                }}
              >
                <option value="">Todas las modalidades</option>
                {catalogos.modalidades.map((mod) => (
                  <option key={mod.codigo} value={mod.codigo}>
                    {mod.nombre}
                  </option>
                ))}
              </select>
            </div>
          </div>
        </section>

        {/* Encabezado de Resultados */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem' }}>
            {cargando ? (
              'Consultando profesionales...'
            ) : (
              <>
                Se encontraron <strong>{totalRegistros}</strong> profesionales habilitados
              </>
            )}
          </p>
          <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>
            Página {pagina} de {totalPaginas}
          </span>
        </div>

        {/* Cuadrícula de Profesionales */}
        {cargando ? (
          <div style={{ textAlign: 'center', padding: '60px 0' }}>
            <p style={{ color: 'var(--text-muted)' }}>Cargando directorio de profesionales...</p>
          </div>
        ) : profesionales.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '60px 0', background: 'white', borderRadius: 16, border: '1px solid var(--border)' }}>
            <AlertCircle size={40} style={{ color: 'var(--text-muted)', margin: '0 auto 12px auto' }} />
            <h3 style={{ fontSize: '1.1rem', fontWeight: 600 }}>No se encontraron profesionales</h3>
            <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem', marginTop: 4 }}>
              Intente ajustar los filtros de búsqueda, especialidad o convenio.
            </p>
          </div>
        ) : (
          <div className="professionals-grid">
            {profesionales.map((prof) => {
              const profId = prof.id || prof.id_usuario;
              const nombre = prof.fullName || prof.nombre_completo || 'Profesional de la Salud';
              const foto = prof.img_url || prof.url_foto || 'https://tekerapp.maxapex.net/FILES_DEV_TEKER/logo_circulo.png';
              const tieneCalificacion = prof.rate !== null && prof.rate !== undefined && prof.rate > 0;
              const listaSpecialty = normalizarArreglo<SpecialtyItem>(prof.specialty);
              const listaEspecialidades = normalizarArreglo<{ id: number; nombre: string }>(prof.especialidades);
              const listaModalidades = normalizarArreglo<string>(prof.modalidades);
              const diasServicio: string[] = (() => {
                const raw = prof.days_of_service;
                if (!raw) return [];
                if (Array.isArray(raw)) return raw;
                if (typeof raw === 'string') {
                  const trimmed = raw.trim();
                  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
                    try {
                      const arr = JSON.parse(trimmed);
                      if (Array.isArray(arr)) return arr;
                    } catch {}
                  }
                  return trimmed.split(',').map((d: string) => d.trim()).filter(Boolean);
                }
                return [];
              })();

              return (
                <div key={profId} className="prof-card">
                  <div className="prof-header">
                    <img
                      src={foto}
                      alt={nombre}
                      className="prof-avatar"
                      onError={(e) => {
                        (e.target as HTMLImageElement).src = 'https://tekerapp.maxapex.net/FILES_DEV_TEKER/logo_circulo.png';
                      }}
                      style={{
                        width: 68,
                        height: 68,
                        minWidth: 68,
                        minHeight: 68,
                        maxWidth: 68,
                        maxHeight: 68,
                        borderRadius: '50%',
                        objectFit: 'cover'
                      }}
                    />
                    <div className="prof-info">
                      <h2 className="prof-name">{nombre}</h2>
                      
                      {/* Slug / ID */}
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                        {prof.slug && <span className="prof-slug">@{prof.slug}</span>}
                        <span style={{ fontSize: '0.78rem', color: 'var(--text-muted)' }}>ID: {profId}</span>
                      </div>

                      {/* Calificación y Reseñas */}
                      <div className="prof-rating-row">
                        {tieneCalificacion ? (
                          <>
                            <span className="badge badge-rating">
                              <Star size={12} fill="#ca8a04" color="#ca8a04" />
                              {Number(prof.rate).toFixed(1)}
                            </span>
                            <span className="prof-reviews-count">
                              ({prof.reviews || 0} {prof.reviews === 1 ? 'reseña' : 'reseñas'})
                            </span>
                          </>
                        ) : (
                          <span className="badge" style={{ background: '#f8fafc', color: '#64748b', border: '1px solid #e2e8f0', fontSize: '0.72rem' }}>
                            <Star size={11} color="#94a3b8" />
                            Nuevo
                          </span>
                        )}
                      </div>

                      {/* Badges de Género y Festivos */}
                      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginTop: 6 }}>
                        {prof.gender && (
                          <span className="badge badge-gender">{prof.gender}</span>
                        )}
                        {prof.trabaja_festivos === 'S' && (
                          <span className="badge badge-festivo">Labora Festivos</span>
                        )}
                      </div>
                    </div>
                  </div>

                  <div className="prof-body">
                    {/* Subespecialidad destacada si existe */}
                    {prof.subspecialty && (
                      <div style={{ marginBottom: 8 }}>
                        <span className="badge badge-subspecialty" title="Subespecialidad principal">
                          <Award size={12} style={{ marginRight: 4, display: 'inline' }} />
                          {prof.subspecialty}
                        </span>
                      </div>
                    )}

                    {/* Catálogo de Especialidades */}
                    <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 12 }}>
                      {listaSpecialty.length > 0 ? (
                        listaSpecialty.map((esp) => (
                          <span key={esp.id} className="badge badge-specialty">
                            <Stethoscope size={12} style={{ marginRight: 4, display: 'inline' }} />
                            {esp.nombre_especialidad}
                          </span>
                        ))
                      ) : listaEspecialidades.length > 0 ? (
                        listaEspecialidades.map((esp) => (
                          <span key={esp.id} className="badge badge-specialty">
                            <Stethoscope size={12} style={{ marginRight: 4, display: 'inline' }} />
                            {esp.nombre}
                          </span>
                        ))
                      ) : prof.esp_subesp ? (
                        <span className="badge badge-specialty">
                          <Stethoscope size={12} style={{ marginRight: 4, display: 'inline' }} />
                          {prof.esp_subesp}
                        </span>
                      ) : (
                        <span className="badge badge-specialty">
                          <Stethoscope size={12} style={{ marginRight: 4, display: 'inline' }} />
                          Medicina General
                        </span>
                      )}
                    </div>

                    {/* Modalidades de Atención */}
                    <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 10 }}>
                      {listaModalidades.includes('V') && (
                        <span className="badge badge-modality">
                          <Video size={12} style={{ marginRight: 4, display: 'inline' }} />
                          Virtual
                        </span>
                      )}
                      {listaModalidades.includes('D') && (
                        <span className="badge badge-modality">
                          <MapPin size={12} style={{ marginRight: 4, display: 'inline' }} />
                          Domiciliaria
                        </span>
                      )}
                    </div>

                    {/* Días de Atención / Horarios */}
                    <div className="prof-days-container">
                      <div className="prof-days-header">
                        <Calendar size={12} style={{ marginRight: 5, color: '#4338ca' }} />
                        <span className="prof-days-title">Días de servicio:</span>
                      </div>
                      {diasServicio.length > 0 ? (
                        <div className="prof-days-chips">
                          {diasServicio.map((dia) => (
                            <span key={dia} className="badge-day-pill" title={`Horario configurado para el día ${dia}`}>
                              {dia}
                            </span>
                          ))}
                        </div>
                      ) : (
                        <span className="prof-days-empty-text">Sin horarios en el rango</span>
                      )}
                    </div>

                    {/* Contacto opcional */}
                    {prof.correo && (
                      <p style={{ fontSize: '0.82rem', color: 'var(--text-muted)', marginBottom: 2 }}>
                        <strong>Correo:</strong> {prof.correo}
                      </p>
                    )}
                    {prof.telefono && (
                      <p style={{ fontSize: '0.82rem', color: 'var(--text-muted)' }}>
                        <strong>Teléfono:</strong> {prof.telefono}
                      </p>
                    )}
                  </div>

                  <div className="prof-footer">
                    <button
                      type="button"
                      className="btn-availability"
                      onClick={() => abrirDisponibilidad(prof)}
                    >
                      <Clock size={16} />
                      <span>Ver Disponibilidad</span>
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* Paginación */}
        {totalPaginas > 1 && (
          <div className="pagination">
            <button
              type="button"
              className="page-btn"
              disabled={pagina <= 1}
              onClick={() => setPagina((prev) => Math.max(prev - 1, 1))}
            >
              <ChevronLeft size={16} />
            </button>
            {Array.from({ length: totalPaginas }).map((_, idx) => {
              const num = idx + 1;
              return (
                <button
                  key={num}
                  type="button"
                  className={`page-btn ${pagina === num ? 'active' : ''}`}
                  onClick={() => setPagina(num)}
                >
                  {num}
                </button>
              );
            })}
            <button
              type="button"
              className="page-btn"
              disabled={pagina >= totalPaginas}
              onClick={() => setPagina((prev) => Math.min(prev + 1, totalPaginas))}
            >
              <ChevronRight size={16} />
            </button>
          </div>
        )}
      </main>

      {/* Modal 1: Disponibilidad Horaria con Selector de Día del Rango */}
      {medicoSeleccionado && (
        <div className="modal-overlay" onClick={() => setMedicoSeleccionado(null)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <img
                  src={medicoSeleccionado.url_foto || 'https://tekerapp.maxapex.net/FILES_DEV_TEKER/logo_circulo.png'}
                  alt={medicoSeleccionado.nombre_completo}
                  className="prof-avatar"
                  style={{
                    width: 48,
                    height: 48,
                    minWidth: 48,
                    minHeight: 48,
                    maxWidth: 48,
                    maxHeight: 48,
                    borderRadius: '50%',
                    objectFit: 'cover'
                  }}
                />
                <div>
                  <h3 style={{ fontSize: '1.15rem', fontWeight: 700 }}>
                    Disponibilidad: {medicoSeleccionado.nombre_completo}
                  </h3>
                  <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>
                    Aseguramiento: {idTipoAseguramiento === 1 ? 'Voluntario' : 'Obligatorio'} | Modalidad:{' '}
                    {modalidad === 'D' ? 'Domiciliaria' : 'Virtual'}
                  </p>
                </div>
              </div>
              <button type="button" className="close-btn" onClick={() => setMedicoSeleccionado(null)}>
                <X size={20} />
              </button>
            </div>

            <div className="modal-body">
              {cargandoSlots ? (
                <div style={{ textAlign: 'center', padding: '40px 0' }}>
                  <p style={{ color: 'var(--text-muted)' }}>
                    Verificando disponibilidad para el profesional en el rango seleccionado...
                  </p>
                </div>
              ) : totalSlotsRangoModal === 0 || diasDisponiblesModal.length === 0 ? (
                /* Caso: El profesional NO tiene ningún intervalo de disponibilidad en todo el rango */
                <div className="call-center-card">
                  <div className="call-center-icon-wrapper">
                    <PhoneCall size={32} />
                  </div>
                  <h4 className="call-center-title">
                    Llamar el call center para coordinar la programacion de la atencion
                  </h4>
                  <p className="call-center-desc">
                    El profesional no cuenta con turnos disponibles en el rango de fechas seleccionado (
                    <strong>{fechaInicio}</strong> al <strong>{fechaFin}</strong>). Comuníquese con nuestra central telefónica de citas para coordinar su asignación.
                  </p>
                  <a href="tel:018000000000" className="call-center-phone-btn">
                    <PhoneCall size={18} />
                    <span>Llamar a Call Center</span>
                  </a>
                </div>
              ) : (
                /* Caso: El profesional sí tiene días con disponibilidad. Solo se visualizan los días con intervalos */
                <div>
                  {/* Selector de Días del Rango de Fechas (únicamente días con disponibilidad) */}
                  <div className="days-container">
                    <label className="form-label" style={{ marginBottom: 8, display: 'block' }}>
                      Seleccione un día del rango para consultar los intervalos:
                    </label>
                    <div className="days-scroll">
                      {diasDisponiblesModal.map((item) => (
                        <div
                          key={item.fecha}
                          className={`day-chip ${diaSeleccionadoModal === item.fecha ? 'active' : ''}`}
                          onClick={() => seleccionarDiaModal(item.fecha)}
                        >
                          <span className="day-name">{item.diaNombre}</span>
                          <span className="day-num">{item.diaNum}</span>
                          <span className="day-month">{item.mesNombre}</span>
                        </div>
                      ))}
                    </div>
                  </div>

                  {slotsData && (
                    <div>
                      {/* Badge de Jerarquía de Horario Aplicado */}
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
                        <span style={{ fontSize: '0.85rem', fontWeight: 600 }}>Jerarquía de Horario:</span>
                        <span
                          style={{
                            fontSize: '0.75rem',
                            fontWeight: 700,
                            padding: '4px 10px',
                            borderRadius: 8,
                            background:
                              slotsData.tipo_horario_aplica === 'POR_DIA'
                                ? '#dcfce7'
                                : slotsData.tipo_horario_aplica === 'PERSONALIZADO'
                                ? '#e0e7ff'
                                : '#f1f5f9',
                            color:
                              slotsData.tipo_horario_aplica === 'POR_DIA'
                                ? '#166534'
                                : slotsData.tipo_horario_aplica === 'PERSONALIZADO'
                                ? '#3730a3'
                                : '#475569'
                          }}
                        >
                          {slotsData.tipo_horario_aplica === 'POR_DIA' && 'Prioridad 1: Horario por Día'}
                          {slotsData.tipo_horario_aplica === 'PERSONALIZADO' && 'Prioridad 2: Horario Personalizado'}
                          {slotsData.tipo_horario_aplica === 'BASE' && 'Prioridad 3: Horario Base Permanente'}
                          {slotsData.tipo_horario_aplica === 'NINGUNO' && 'Sin Horario Programado'}
                          {slotsData.tipo_horario_aplica === 'ERROR' && 'Error'}
                        </span>
                        <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                          (Duración cita: {slotsData.duracion_cita_min} min)
                        </span>
                      </div>

                      {/* Mensaje de estado */}
                      {slotsData.slots.length === 0 ? (
                        <div className="alert-info">
                          <p>
                            <strong>Nota:</strong> {slotsData.mensaje || 'No hay intervalos disponibles para esta fecha.'}
                          </p>
                        </div>
                      ) : (
                        <div>
                          <p style={{ fontSize: '0.9rem', fontWeight: 600, color: 'var(--text-main)' }}>
                            Intervalos disponibles para el {diaSeleccionadoModal} ({slotsData.slots.length} turnos):
                          </p>
                          <div className="slots-grid">
                            {slotsData.slots.map((slot, idx) => (
                              <div
                                key={idx}
                                className={`slot-pill ${
                                  slotSeleccionado?.hora_inicio === slot.hora_inicio ? 'selected' : ''
                                }`}
                                onClick={() => setSlotSeleccionado(slot)}
                              >
                                {slot.hora_inicio}
                              </div>
                            ))}
                          </div>

                          {slotSeleccionado && (
                            <div
                              style={{
                                marginTop: 20,
                                padding: 16,
                                background: '#f8fafc',
                                borderRadius: 10,
                                border: '1px solid var(--border)'
                              }}
                            >
                              <p style={{ fontWeight: 600, color: 'var(--primary)' }}>
                                Intervalo Seleccionado: {slotSeleccionado.hora_inicio} - {slotSeleccionado.hora_fin} (
                                {slotSeleccionado.duracion_minutos} min)
                              </p>
                              <button
                                type="button"
                                className="btn-availability"
                                style={{ marginTop: 10 }}
                                onClick={() =>
                                  alert(
                                    `Cita seleccionada con éxito para el profesional ${medicoSeleccionado.nombre_completo} el día ${diaSeleccionadoModal} a las ${slotSeleccionado.hora_inicio}`
                                  )
                                }
                              >
                                Confirmar Reserva de Cita
                              </button>
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Modal 2: Consola de Diagnóstico / Bloque Anónimo PL/SQL (Ctrl + Alt + D) */}
      {mostrarModalDebug && (
        <div className="modal-overlay" onClick={() => setMostrarModalDebug(false)}>
          <div className="modal-content debug-modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <Terminal size={22} style={{ color: 'var(--primary)' }} />
                <div>
                  <h3 style={{ fontSize: '1.15rem', fontWeight: 700 }}>
                    Consola de Depuración PL/SQL (Ctrl + Alt + D)
                  </h3>
                  <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>
                    {payloadActual.procedimiento}
                  </p>
                </div>
              </div>
              <button type="button" className="close-btn" onClick={() => setMostrarModalDebug(false)}>
                <X size={20} />
              </button>
            </div>

            <div className="modal-body">
              {/* Explicación del Procedimiento */}
              <div style={{ marginBottom: 16 }}>
                <p style={{ fontSize: '0.9rem', color: 'var(--text-main)', lineHeight: 1.5 }}>
                  {payloadActual.descripcion}
                </p>
              </div>

              {/* Bloque Anónimo con Botón de Copiar */}
              <div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: '0.85rem', fontWeight: 700, color: 'var(--text-main)' }}>
                    Bloque Anónimo Oracle PL/SQL (Listo para ejecutar en SQL Developer / PL/SQL Developer / Toad):
                  </span>
                </div>

                <div className="code-block-container">
                  <button
                    type="button"
                    className={`btn-copy-code ${copiado ? 'copied' : ''}`}
                    onClick={copiarAlPortapapeles}
                  >
                    {copiado ? <Check size={14} /> : <Copy size={14} />}
                    <span>{copiado ? '¡Copiado!' : 'Copiar Bloque PL/SQL'}</span>
                  </button>
                  <pre style={{ margin: 0 }}>
                    <code>{codigoPlsqlAnonimo}</code>
                  </pre>
                </div>
              </div>

              {/* Tabla de Explicación de Parámetros de Entrada */}
              <div style={{ marginTop: 24 }}>
                <h4 style={{ fontSize: '0.95rem', fontWeight: 700, marginBottom: 8 }}>
                  Diccionario de Parámetros de Entrada (Payload JSON de Entrada):
                </h4>
                <div style={{ overflowX: 'auto' }}>
                  <table className="debug-table">
                    <thead>
                      <tr>
                        <th>Campo</th>
                        <th>Tipo</th>
                        <th>Obligatorio</th>
                        <th>Descripción</th>
                        <th>Valor Actual</th>
                      </tr>
                    </thead>
                    <tbody>
                      {payloadActual.parametrosDoc.map((param) => (
                        <tr key={param.campo}>
                          <td>
                            <code>{param.campo}</code>
                          </td>
                          <td>{param.tipo}</td>
                          <td>
                            <span
                              style={{
                                color: param.obligatorio === 'SÍ' ? '#dc2626' : '#64748b',
                                fontWeight: param.obligatorio === 'SÍ' ? 700 : 500
                              }}
                            >
                              {param.obligatorio}
                            </span>
                          </td>
                          <td>{param.descripcion}</td>
                          <td>
                            <strong>{param.ejemplo}</strong>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>

              {/* Tabla de Explicación de Salida del Método */}
              <div style={{ marginTop: 24 }}>
                <h4 style={{ fontSize: '0.95rem', fontWeight: 700, marginBottom: 8 }}>
                  Estructura de Salida del Método (Payload JSON de Respuesta):
                </h4>
                <div style={{ overflowX: 'auto' }}>
                  <table className="debug-table">
                    <thead>
                      <tr>
                        <th>Campo de Salida</th>
                        <th>Tipo</th>
                        <th>Descripción y Contenido</th>
                      </tr>
                    </thead>
                    <tbody>
                      {payloadActual.salidaDoc.map((out) => (
                        <tr key={out.campo}>
                          <td>
                            <code style={{ color: '#059669', background: '#ecfdf5' }}>{out.campo}</code>
                          </td>
                          <td>{out.tipo}</td>
                          <td>{out.descripcion}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>

                {/* Ejemplo de JSON de Salida */}
                {payloadActual.ejemploSalidaJson && (
                  <div style={{ marginTop: 14 }}>
                    <span style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-muted)' }}>
                      Ejemplo de JSON de Respuesta:
                    </span>
                    <pre
                      style={{
                        background: '#0f172a',
                        color: '#38bdf8',
                        padding: 14,
                        borderRadius: 8,
                        fontSize: '0.8rem',
                        overflowX: 'auto',
                        marginTop: 6,
                        border: '1px solid #334155'
                      }}
                    >
                      <code>{payloadActual.ejemploSalidaJson}</code>
                    </pre>
                  </div>
                )}
              </div>

              {/* Reglas de Negocio Destacadas */}
              <div style={{ marginTop: 24 }}>
                <h4 style={{ fontSize: '0.95rem', fontWeight: 700, marginBottom: 8, color: '#1e3a8a' }}>
                  Reglas de Negocio y Estándares Aplicados:
                </h4>
                <div
                  style={{
                    background: '#f8fafc',
                    border: '1.5px solid #e2e8f0',
                    borderRadius: 8,
                    padding: '14px 18px'
                  }}
                >
                  <ul style={{ margin: 0, paddingLeft: 20, fontSize: '0.85rem', lineHeight: 1.6, color: '#334155' }}>
                    {payloadActual.reglasNegocio.map((regla, idx) => (
                      <li key={idx} style={{ marginBottom: 6 }}>
                        {regla}
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
