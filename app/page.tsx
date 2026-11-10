'use client';

import React, { useState, useEffect, useCallback, useMemo } from 'react';
import * as XLSX from 'xlsx';
import {
  Search,
  Calendar,
  Clock,
  MapPin,
  Video,
  Stethoscope,
  ChevronLeft,
  ChevronRight,
  ChevronDown,
  ChevronUp,
  X,
  AlertCircle,
  Copy,
  Check,
  Terminal,
  Code2,
  PhoneCall,
  Star,
  Award,
  Sparkles,
  Layers,
  UserX,
  CalendarX,
  FileSpreadsheet,
  Download,
  Users,
  Mail,
  Phone,
  Database,
  RefreshCw,
  CheckCircle2,
  Server
} from 'lucide-react';


interface ProfesionalSinDisp {
  id_usuario: number;
  nombre_completo: string;
  correo?: string;
  telefono?: string;
  days_of_service?: string[] | string | null;
  motivo?: string;
}

interface EspecialidadSinDisp {
  id_especialidad: number;
  nombre_especialidad: string;
  tiene_profesionales: boolean;
  tipo: 'SIN_PROFESIONALES' | 'CON_PROFESIONALES_SIN_DISPONIBILIDAD';
  total_profesionales: number;
  profesionales: ProfesionalSinDisp[];
}

interface RespuestaSinDisp {
  codigo: number;
  mensaje: string;
  fecha_inicio: string;
  fecha_fin: string;
  total_sin_disponibilidad: number;
  total_especialidades_sin_medicos?: number;
  total_medicos_sin_cupos?: number;
  especialidades: EspecialidadSinDisp[];
}

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

function formatearFechaLocal(fecha: Date): string {
  const y = fecha.getFullYear();
  const m = String(fecha.getMonth() + 1).padStart(2, '0');
  const d = String(fecha.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function getFechaManana(): string {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  return formatearFechaLocal(d);
}

function getFechaFinDefecto(fIniStr?: string): string {
  let d: Date;
  if (fIniStr && fIniStr.includes('-')) {
    const [y, m, dia] = fIniStr.split('-').map(Number);
    d = new Date(y, m - 1, dia);
  } else {
    d = new Date();
    d.setDate(d.getDate() + 1);
  }
  d.setDate(d.getDate() + 6);
  return formatearFechaLocal(d);
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
  const [idProfesionalesExcluir, setIdProfesionalesExcluir] = useState<string>('');
  const [pagina, setPagina] = useState(1);

  // Rango de fechas de consulta (por defecto mañana)
  const [fechaInicio, setFechaInicio] = useState<string>(() => getFechaManana());
  const [fechaFin, setFechaFin] = useState<string>(() => getFechaFinDefecto());

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


  // Modal de Profesionales Sin Disponibilidad
  const [mostrarModalSinDisp, setMostrarModalSinDisp] = useState(false);
  const [cargandoSinDisp, setCargandoSinDisp] = useState(false);
  const [datosSinDisp, setDatosSinDisp] = useState<RespuestaSinDisp | null>(null);
  const [busquedaSinDisp, setBusquedaSinDisp] = useState('');
  const [filtroTipoSinDisp, setFiltroTipoSinDisp] = useState<'TODAS' | 'SIN_MEDICOS' | 'CON_MEDICOS'>('TODAS');
  const [especialidadesContraidas, setEspecialidadesContraidas] = useState<Set<number>>(new Set());

  // Modal de depuración PL/SQL (Ctrl + Alt + D) y prueba de conexión a Oracle
  const [mostrarModalDebug, setMostrarModalDebug] = useState(false);
  const [tabDebugActiva, setTabDebugActiva] = useState<'plsql' | 'conexion'>('plsql');
  const [procedimientoDebugSeleccionado, setProcedimientoDebugSeleccionado] = useState<
    'directorio' | 'disponibilidad' | 'filtros' | 'sin_disponibilidad'
  >('directorio');
  const [copiado, setCopiado] = useState(false);
  const [probandoConexion, setProbandoConexion] = useState(false);
  const [resultadoConexion, setResultadoConexion] = useState<any>(null);

  const probarConexionOracle = useCallback(async () => {
    setProbandoConexion(true);
    try {
      const res = await fetch('/api/test-db', { cache: 'no-store' });
      const data = await res.json();
      setResultadoConexion(data);
    } catch (err: any) {
      setResultadoConexion({
        conectado: false,
        mensaje: err?.message || 'Error de red al consultar /api/test-db',
        codigo_oracle: 'ERR_NETWORK'
      });
    } finally {
      setProbandoConexion(false);
    }
  }, []);


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

  // Listener para atajo de teclado Ctrl + Alt + D (sin botón visible en interfaz)
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.ctrlKey && e.altKey && (e.key === 'd' || e.key === 'D')) {
        e.preventDefault();
        setMostrarModalDebug((prev) => {
          const next = !prev;
          if (next) {
            if (mostrarModalSinDisp) {
              setProcedimientoDebugSeleccionado('sin_disponibilidad');
            } else if (medicoSeleccionado) {
              setProcedimientoDebugSeleccionado('disponibilidad');
            } else {
              setProcedimientoDebugSeleccionado('directorio');
            }
          }
          return next;
        });
      }
      if (e.key === 'Escape') {
        setMostrarModalDebug(false);
      }
    }
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [mostrarModalSinDisp, medicoSeleccionado]);

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
        fecha_a_partir_de: fechaInicio,
        fecha_inicio: fechaInicio,
        fecha_fin: fechaFin,
        id_profesionales_excluir: idProfesionalesExcluir.trim() || null
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
  }, [pagina, busqueda, idEspecialidad, idConvenio, idTipoAseguramiento, modalidad, fechaInicio, fechaFin, idProfesionalesExcluir]);

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



  // Apertura y consulta de profesionales y especialidades sin disponibilidad
  const abrirModalSinDisponibilidad = async () => {
    setMostrarModalSinDisp(true);
    setCargandoSinDisp(true);
    setBusquedaSinDisp('');
    setFiltroTipoSinDisp('TODAS');
    try {
      const params = new URLSearchParams({
        fecha_inicio: fechaInicio,
        fecha_fin: fechaFin,
        id_convenio: idConvenio ? String(idConvenio) : '',
        id_tipo_aseguramiento: String(idTipoAseguramiento),
        modalidad: modalidad || 'V'
      });
      const res = await fetch(`/api/sin-disponibilidad?${params.toString()}`);
      const data: any = await res.json();
      setEspecialidadesContraidas(new Set());

      setDatosSinDisp({
        codigo: data?.codigo ?? 0,
        mensaje: data?.mensaje ?? '',
        fecha_inicio: data?.fecha_inicio ?? fechaInicio,
        fecha_fin: data?.fecha_fin ?? fechaFin,
        total_sin_disponibilidad: data?.total_sin_disponibilidad ?? (data?.especialidades?.length || 0),
        total_especialidades_sin_medicos: data?.total_especialidades_sin_medicos ?? 0,
        total_medicos_sin_cupos: data?.total_medicos_sin_cupos ?? 0,
        especialidades: Array.isArray(data?.especialidades) ? data.especialidades : []
      });
    } catch (err) {
      console.error('Error al consultar especialidades sin disponibilidad:', err);
      setDatosSinDisp({
        codigo: -1,
        mensaje: 'Error de conexión con el servidor',
        fecha_inicio: fechaInicio,
        fecha_fin: fechaFin,
        total_sin_disponibilidad: 0,
        total_especialidades_sin_medicos: 0,
        total_medicos_sin_cupos: 0,
        especialidades: []
      });
    } finally {
      setCargandoSinDisp(false);
    }
  };

  // Exportar listado de sin disponibilidad a formato Excel (.xlsx)
  const exportarExcelSinDisponibilidad = () => {
    if (!datosSinDisp || !datosSinDisp.especialidades || datosSinDisp.especialidades.length === 0) {
      return;
    }

    const filas: any[] = [];
    datosSinDisp.especialidades.forEach((esp) => {
      if (!esp.tiene_profesionales || esp.profesionales.length === 0) {
        filas.push({
          'Especialidad': esp.nombre_especialidad,
          'ID Médico': '-',
          'Nombre del Profesional': 'Sin médicos asignados a la especialidad',
          'Días de Atención Habitual': 'N/A',
          'Correo Electrónico': 'N/A',
          'Teléfono': 'N/A',
          'Rango Evaluado': `${datosSinDisp.fecha_inicio} al ${datosSinDisp.fecha_fin}`,
          'Estado Disponibilidad': 'Especialidad sin profesionales registrados'
        });
      } else {
        esp.profesionales.forEach((doc) => {
          let diasTexto = 'Sin horarios';
          if (Array.isArray(doc.days_of_service)) {
            diasTexto = doc.days_of_service.length > 0 ? doc.days_of_service.join(', ') : 'Sin horarios';
          } else if (typeof doc.days_of_service === 'string') {
            diasTexto = doc.days_of_service || 'Sin horarios';
          }

          filas.push({
            'Especialidad': esp.nombre_especialidad,
            'ID Médico': doc.id_usuario,
            'Nombre del Profesional': doc.nombre_completo,
            'Días de Atención Habitual': diasTexto,
            'Correo Electrónico': doc.correo || 'No registrado',
            'Teléfono': doc.telefono || 'No registrado',
            'Rango Evaluado': `${datosSinDisp.fecha_inicio} al ${datosSinDisp.fecha_fin}`,
            'Estado Disponibilidad': 'Sin disponibilidad (0 cupos en el rango)'
          });
        });
      }
    });

    const ws = XLSX.utils.json_to_sheet(filas);
    ws['!cols'] = [
      { wch: 30 },
      { wch: 12 },
      { wch: 38 },
      { wch: 26 },
      { wch: 30 },
      { wch: 18 },
      { wch: 26 },
      { wch: 35 }
    ];

    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, 'Sin Disponibilidad');
    const nombreArchivo = `Reporte_Sin_Disponibilidad_${datosSinDisp.fecha_inicio}_al_${datosSinDisp.fecha_fin}.xlsx`;
    XLSX.writeFile(wb, nombreArchivo);
  };


  // Control de expansión / contracción de especialidades
  const toggleEspecialidad = (idEsp: number) => {
    setEspecialidadesContraidas((prev) => {
      const next = new Set(prev);
      if (next.has(idEsp)) {
        next.delete(idEsp);
      } else {
        next.add(idEsp);
      }
      return next;
    });
  };

  const expandirTodas = () => {
    setEspecialidadesContraidas(new Set());
  };

  const contraerTodas = () => {
    const todosLosIds = new Set<number>();
    (datosSinDisp?.especialidades || []).forEach((esp) => {
      todosLosIds.add(esp.id_especialidad);
    });
    setEspecialidadesContraidas(todosLosIds);
  };

  // Filtrado reactivo dentro del modal por pestaña y búsqueda
  const especialidadesFiltradasSinDisp = useMemo(() => {
    if (!datosSinDisp?.especialidades) return [];
    let lista = datosSinDisp.especialidades;

    // Filtro por pestaña
    if (filtroTipoSinDisp === 'SIN_MEDICOS') {
      lista = lista.filter((e) => !e.tiene_profesionales || e.profesionales.length === 0);
    } else if (filtroTipoSinDisp === 'CON_MEDICOS') {
      lista = lista.filter((e) => e.tiene_profesionales && e.profesionales.length > 0);
    }

    // Filtro por texto de búsqueda
    const q = busquedaSinDisp.trim().toLowerCase();
    if (!q) return lista;

    return lista
      .map((esp) => {
        const coincideEsp = esp.nombre_especialidad.toLowerCase().includes(q);
        if (coincideEsp) return esp;

        if (esp.profesionales && esp.profesionales.length > 0) {
          const docs = esp.profesionales.filter(
            (doc) =>
              doc.nombre_completo.toLowerCase().includes(q) ||
              (doc.correo && doc.correo.toLowerCase().includes(q)) ||
              (doc.telefono && doc.telefono.includes(q))
          );
          if (docs.length > 0) {
            return {
              ...esp,
              profesionales: docs,
              total_profesionales: docs.length
            };
          }
        }
        return null;
      })
      .filter(Boolean) as EspecialidadSinDisp[];
  }, [datosSinDisp, busquedaSinDisp, filtroTipoSinDisp]);

  // Catálogo completo de procedimientos PL/SQL que el aplicativo invoca en Oracle Database
  const catalogoProcedimientosPlsql = useMemo(() => {
    const idMedicoEjemplo = medicoSeleccionado?.id || medicoSeleccionado?.id_usuario || profesionales[0]?.id || profesionales[0]?.id_usuario || 65;

    return {
      directorio: {
        key: 'directorio' as const,
        etiquetaCorta: '1. p_consultar_directorio',
        endpointApi: 'POST /api/directorio',
        procedimiento: 'PKGLN_DIRECTORIO_PROFESIONALES.p_consultar_directorio',
        descripcion:
          'Consulta el directorio paginado de profesionales habilitados (id_estado_usuario = 1, id_rol = 4 o en tkr_roles_usuario y con franja horaria activa) aplicando filtros multidimensionales y evaluando los días de servicio en el rango de fechas.',
        jsonEntrada: {
          pagina,
          registros_por_pagina: 12,
          busqueda: busqueda.trim() || null,
          id_especialidad: idEspecialidad || null,
          id_convenio: idConvenio || null,
          id_tipo_aseguramiento: idTipoAseguramiento || null,
          modalidad: modalidad || null,
          fecha_a_partir_de: fechaInicio,
          fecha_inicio: fechaInicio,
          fecha_fin: fechaFin,
          id_profesionales_excluir: idProfesionalesExcluir.trim() || null
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
            tipo: 'VARCHAR2(200)',
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
          },
          {
            campo: 'fecha_a_partir_de / fecha_inicio',
            tipo: 'VARCHAR2(10)',
            obligatorio: 'NO',
            descripcion: 'Fecha a partir de la cual consultar los horarios/días de servicio activos en formato YYYY-MM-DD. Por defecto: mañana (SYSDATE + 1)',
            ejemplo: `'${fechaInicio}'`
          },
          {
            campo: 'fecha_fin',
            tipo: 'VARCHAR2(10)',
            obligatorio: 'NO',
            descripcion: 'Fecha final del rango en formato YYYY-MM-DD para evaluar días de servicio activos',
            ejemplo: `'${fechaFin}'`
          },
          {
            campo: 'id_profesionales_excluir',
            tipo: 'VARCHAR2(4000)',
            obligatorio: 'NO',
            descripcion: 'Cadena con IDs de profesionales a excluir separados por coma (ej: 101,102,105)',
            ejemplo: idProfesionalesExcluir ? `'${idProfesionalesExcluir}'` : 'NULL'
          },
          {
            campo: 'p_devolver_uno',
            tipo: 'VARCHAR2(1)',
            obligatorio: 'NO',
            descripcion: "Si viene en 'S', devuelve únicamente 1 profesional aleatorio de los que tienen horario activo ('N' por defecto)",
            ejemplo: "'S'"
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
              'Arreglo de objetos de profesionales habilitados: id_usuario (NUMBER), fullName / nombre_completo (VARCHAR2), correo (VARCHAR2), telefono (VARCHAR2), trabaja_festivos ("S"/"N"), url_foto (VARCHAR2), especialidades (JSON_ARRAY), modalidades (JSON_ARRAY ["V","D"]), days_of_service (días con horario en el rango).'
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
                modalidades: ['V', 'D'],
                days_of_service: ['LU', 'MA', 'MI', 'JU', 'VI']
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
      },

      disponibilidad: {
        key: 'disponibilidad' as const,
        etiquetaCorta: '2. p_consultar_disponibilidad',
        endpointApi: 'POST /api/disponibilidad',
        procedimiento: 'PKGLN_DIRECTORIO_PROFESIONALES.p_consultar_disponibilidad',
        descripcion:
          'Consulta la disponibilidad horaria, jerarquía de turnos (POR_DIA > PERSONALIZADO > BASE) y vector bitmap (288 posiciones de 5 min en tkr_disponibilidad_bitmap) de un profesional para un día específico (DIA) o un rango de fechas (RANGO).',
        jsonEntrada: {
          id_usuario: idMedicoEjemplo,
          fecha: diaSeleccionadoModal || fechaInicio,
          tipo_vista: medicoSeleccionado && !diaSeleccionadoModal ? 'RANGO' : 'DIA',
          fecha_inicio: fechaInicio,
          fecha_fin: fechaFin,
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
            ejemplo: String(idMedicoEjemplo)
          },
          {
            campo: 'fecha',
            tipo: 'VARCHAR2(10)',
            obligatorio: 'SÍ (en vista DIA)',
            descripcion: 'Fecha a consultar en formato obligatorio ISO YYYY-MM-DD',
            ejemplo: `'${diaSeleccionadoModal || fechaInicio}'`
          },
          {
            campo: 'tipo_vista',
            tipo: 'VARCHAR2(10)',
            obligatorio: 'NO',
            descripcion: "'DIA' para cálculo de slots de una fecha puntual, 'SEMANA' para 7 días o 'RANGO' para evaluar entre fecha_inicio y fecha_fin",
            ejemplo: "'DIA'"
          },
          {
            campo: 'fecha_inicio / fecha_fin',
            tipo: 'VARCHAR2(10)',
            obligatorio: 'SÍ (en vista RANGO)',
            descripcion: 'Límites del rango de fechas en formato YYYY-MM-DD cuando tipo_vista = RANGO',
            ejemplo: `'${fechaInicio}' a '${fechaFin}'`
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
            descripcion: '1 = Voluntario (Prepagada/Póliza), 2 = Obligatorio (EPS). Si una franja tiene NULL en BD, aplica para ambos.',
            ejemplo: String(idTipoAseguramiento || 1)
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
            descripcion: 'Número total de intervalos de cita calculados y disponibles para la fecha (o total_slots_rango en vista RANGO)'
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
            id_usuario: idMedicoEjemplo,
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
          'Cruce con Bitmap Ocupado: Descuenta automáticamente los bloques de 5 minutos marcados con "1" en tkr_disponibilidad_bitmap.bitmap_ocupado y los turnos anteriores a f_fecha_actual.',
          'Ausencias y Festivos: Las ausencias programadas (tkr_ausencias_profesional) bloquean la fecha completa devolviendo total_slots: 0 y motivo_bloqueo: AUSENCIA_PROGRAMADA. Festivos y domingos se bloquean salvo que el profesional tenga trabaja_festivos = S o cuente con un Horario por Día explícito.'
        ]
      },

      filtros: {
        key: 'filtros' as const,
        etiquetaCorta: '3. p_consultar_filtros',
        endpointApi: 'GET /api/filtros',
        procedimiento: 'PKGLN_DIRECTORIO_PROFESIONALES.p_consultar_filtros',
        descripcion:
          'Recupera en una única llamada los catálogos maestros requeridos para inicializar los selectores de filtrado del Directorio de Profesionales: especialidades médicas activas, convenios/aseguradoras, tipos de aseguramiento y modalidades de atención.',
        jsonEntrada: {},
        parametrosDoc: [
          {
            campo: 'p_json_entrada',
            tipo: 'CLOB (JSON)',
            obligatorio: 'NO',
            descripcion: 'Objeto JSON vacío ({}) o metadatos opcionales de auditoría (id_usuario_ejecutor, codigo_traza)',
            ejemplo: "'{}'"
          }
        ],
        salidaDoc: [
          {
            campo: 'codigo',
            tipo: 'NUMBER',
            descripcion: '0 = Catálogos cargados exitosamente; negativo en caso de error'
          },
          {
            campo: 'mensaje',
            tipo: 'VARCHAR2',
            descripcion: 'Mensaje de confirmación de la consulta de catálogos'
          },
          {
            campo: 'especialidades',
            tipo: 'JSON_ARRAY',
            descripcion: 'Lista de especialidades [{ id: NUMBER, nombre: VARCHAR2 }] desde tkr_especialidades'
          },
          {
            campo: 'convenios',
            tipo: 'JSON_ARRAY',
            descripcion: 'Lista de convenios activos [{ id: NUMBER, nombre: VARCHAR2 }] desde tkr_convenios'
          },
          {
            campo: 'tipos_aseguramiento',
            tipo: 'JSON_ARRAY',
            descripcion: 'Lista de tipos de aseguramiento [{ id: 1, nombre: "Voluntario" }, { id: 2, nombre: "Obligatorio" }] desde tkr_tipos_aseguramiento'
          },
          {
            campo: 'modalidades',
            tipo: 'JSON_ARRAY',
            descripcion: 'Lista de modalidades de atención [{ codigo: "V", nombre: "Virtual" }, { codigo: "D", nombre: "Domiciliaria" }]'
          }
        ],
        ejemploSalidaJson: JSON.stringify(
          {
            codigo: 0,
            mensaje: 'Catálogos de filtros consultados exitosamente',
            especialidades: [
              { id: 10, nombre: 'Medicina General' },
              { id: 25, nombre: 'Pediatría' }
            ],
            convenios: [
              { id: 1, nombre: 'Allianz Salud' },
              { id: 2, nombre: 'Sura Póliza' }
            ],
            tipos_aseguramiento: [
              { id: 1, nombre: 'Voluntario' },
              { id: 2, nombre: 'Obligatorio' }
            ],
            modalidades: [
              { codigo: 'V', nombre: 'Virtual (Telemedicina)' },
              { codigo: 'D', nombre: 'Domiciliaria' }
            ]
          },
          null,
          2
        ),
        reglasNegocio: [
          'Se invoca automáticamente al iniciar la pantalla del Directorio de Profesionales.',
          'Delega la consulta multi-tabla a PKGCN_DIRECTORIO_PROFESIONALES.p_consultar_filtros_catalogo_json respetando el estándar de capas.'
        ]
      },

      sin_disponibilidad: {
        key: 'sin_disponibilidad' as const,
        etiquetaCorta: '4. p_consultar_sin_disponibilidad',
        endpointApi: 'GET / POST /api/sin-disponibilidad',
        procedimiento: 'PKGLN_DIRECTORIO_PROFESIONALES.p_consultar_sin_disponibilidad',
        descripcion:
          'Evalúa todas las especialidades médicas del sistema en un rango de fechas e identifica: (1) Especialidades que no tienen ningún profesional asignado, y (2) Especialidades cuyos profesionales tienen 0 cupos libres en el rango consultado.',
        jsonEntrada: {
          fecha_inicio: fechaInicio,
          fecha_fin: fechaFin,
          id_convenio: idConvenio || null,
          id_tipo_aseguramiento: idTipoAseguramiento || 1,
          modalidad: modalidad || 'V',
          id_especialidad: idEspecialidad || null
        },
        parametrosDoc: [
          {
            campo: 'fecha_inicio',
            tipo: 'VARCHAR2(10)',
            obligatorio: 'SÍ',
            descripcion: 'Fecha inicial del periodo a auditar en formato YYYY-MM-DD',
            ejemplo: `'${fechaInicio}'`
          },
          {
            campo: 'fecha_fin',
            tipo: 'VARCHAR2(10)',
            obligatorio: 'SÍ',
            descripcion: 'Fecha final del periodo a auditar en formato YYYY-MM-DD',
            ejemplo: `'${fechaFin}'`
          },
          {
            campo: 'id_convenio',
            tipo: 'NUMBER(12)',
            obligatorio: 'NO',
            descripcion: 'Identificador del convenio para filtrar la evaluación de cupos (NULL = todos)',
            ejemplo: idConvenio ? String(idConvenio) : 'NULL'
          },
          {
            campo: 'id_tipo_aseguramiento',
            tipo: 'NUMBER(12)',
            obligatorio: 'NO',
            descripcion: 'Tipo de aseguramiento (1 = Voluntario, 2 = Obligatorio)',
            ejemplo: String(idTipoAseguramiento || 1)
          },
          {
            campo: 'modalidad',
            tipo: 'VARCHAR2(1)',
            obligatorio: 'NO',
            descripcion: "Modalidad de atención a evaluar ('V' = Virtual, 'D' = Domiciliaria)",
            ejemplo: `'${modalidad || 'V'}'`
          },
          {
            campo: 'id_especialidad',
            tipo: 'NUMBER(12)',
            obligatorio: 'NO',
            descripcion: 'Permite acotar el reporte a una especialidad específica (NULL evalúa todas)',
            ejemplo: idEspecialidad ? String(idEspecialidad) : 'NULL'
          }
        ],
        salidaDoc: [
          {
            campo: 'codigo',
            tipo: 'NUMBER',
            descripcion: '0 = Reporte generado exitosamente; negativo en caso de error'
          },
          {
            campo: 'mensaje',
            tipo: 'VARCHAR2',
            descripcion: 'Mensaje descriptivo de la operación'
          },
          {
            campo: 'fecha_inicio / fecha_fin',
            tipo: 'VARCHAR2(10)',
            descripcion: 'Rango de fechas auditado en formato YYYY-MM-DD'
          },
          {
            campo: 'total_sin_disponibilidad',
            tipo: 'NUMBER',
            descripcion: 'Cantidad total de especialidades afectadas (sin médicos o con médicos sin cupos)'
          },
          {
            campo: 'total_especialidades_sin_medicos',
            tipo: 'NUMBER',
            descripcion: 'Cantidad de especialidades del catálogo que no tienen profesionales activos vinculados'
          },
          {
            campo: 'total_medicos_sin_cupos',
            tipo: 'NUMBER',
            descripcion: 'Cantidad de profesionales activos que tienen 0 slots disponibles en todo el rango'
          },
          {
            campo: 'especialidades',
            tipo: 'JSON_ARRAY',
            descripcion: 'Arreglo detallado por especialidad con id_especialidad, nombre_especialidad, tiene_profesionales, tipo y arreglo de profesionales con 0 cupos.'
          }
        ],
        ejemploSalidaJson: JSON.stringify(
          {
            codigo: 0,
            mensaje: 'Consulta de especialidades y profesionales sin disponibilidad completada exitosamente',
            fecha_inicio: fechaInicio,
            fecha_fin: fechaFin,
            total_sin_disponibilidad: 2,
            total_especialidades_sin_medicos: 1,
            total_medicos_sin_cupos: 1,
            especialidades: [
              {
                id_especialidad: 14,
                nombre_especialidad: 'Dermatología',
                tiene_profesionales: true,
                tipo: 'CON_PROFESIONALES_SIN_DISPONIBILIDAD',
                total_profesionales: 1,
                profesionales: [
                  {
                    id_usuario: 82,
                    nombre_completo: 'Dra. Laura Méndez',
                    correo: 'laura.mendez@teker.com',
                    telefono: '3109876543',
                    days_of_service: 'LU, MI, VI',
                    motivo: 'Horarios configurados (LU, MI, VI) pero sin slots libres'
                  }
                ]
              },
              {
                id_especialidad: 31,
                nombre_especialidad: 'Neurología Pediátrica',
                tiene_profesionales: false,
                tipo: 'SIN_PROFESIONALES',
                total_profesionales: 0,
                profesionales: []
              }
            ]
          },
          null,
          2
        ),
        reglasNegocio: [
          'Clasificación Dual: Separa claramente las especialidades que carecen de médicos asignados (SIN_PROFESIONALES) de aquellas cuyos médicos no tienen cupos libres en el rango (CON_PROFESIONALES_SIN_DISPONIBILIDAD).',
          'Exportación: Permite alimentar el reporte descargable en Excel (.xlsx) para gestión operativa de agenda.'
        ]
      }
    };
  }, [
    medicoSeleccionado,
    profesionales,
    diaSeleccionadoModal,
    fechaInicio,
    fechaFin,
    idConvenio,
    idTipoAseguramiento,
    modalidad,
    pagina,
    busqueda,
    idEspecialidad
  ]);

  const payloadActual = catalogoProcedimientosPlsql[procedimientoDebugSeleccionado];

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
              <span style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-muted)' }}>Horarios a partir de:</span>
              <input
                type="date"
                className="form-control"
                style={{ width: 145 }}
                value={fechaInicio}
                onChange={(e) => {
                  const val = e.target.value;
                  setFechaInicio(val);
                  if (val && (!fechaFin || fechaFin < val)) {
                    setFechaFin(getFechaFinDefecto(val));
                  }
                }}
              />
              <span style={{ color: 'var(--text-muted)', fontSize: '0.85rem' }}>hasta</span>
              <input
                type="date"
                className="form-control"
                style={{ width: 145 }}
                value={fechaFin}
                min={fechaInicio}
                onChange={(e) => setFechaFin(e.target.value)}
              />
            </div>
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

            {/* Excluir Profesionales por ID */}
            <div className="form-group">
              <label className="form-label">Excluir IDs (separados por coma)</label>
              <input
                type="text"
                className="form-control"
                placeholder="ej: 101, 102, 105"
                value={idProfesionalesExcluir}
                onChange={(e) => {
                  setIdProfesionalesExcluir(e.target.value);
                  setPagina(1);
                }}
              />
            </div>
          </div>
        </section>

        {/* Encabezado de Resultados */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16, flexWrap: 'wrap', gap: 12 }}>
          <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem' }}>
            {cargando ? (
              'Consultando profesionales...'
            ) : (
              <>
                Se encontraron <strong>{totalRegistros}</strong> profesionales habilitados
              </>
            )}
          </p>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
            {/* Botón Sin Disponibilidad */}
            <button
              type="button"
              className="btn-sin-disp"
              onClick={abrirModalSinDisponibilidad}
              title="Ver profesionales que no tienen disponibilidad en el rango seleccionado"
            >
              <CalendarX size={16} />
              <span>Sin Disponibilidad</span>
            </button>

            <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>
              Página {pagina} de {totalPaginas}
            </span>
          </div>
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

      {/* Modal 2: Consola de Diagnóstico / Bloque Anónimo PL/SQL y Prueba de Conexión (Ctrl + Alt + D) */}
      {mostrarModalDebug && (
        <div className="modal-overlay" onClick={() => setMostrarModalDebug(false)}>
          <div className="modal-content debug-modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <Terminal size={22} style={{ color: 'var(--primary)' }} />
                <div>
                  <h3 style={{ fontSize: '1.15rem', fontWeight: 700 }}>
                    Documentación y Consola PL/SQL (Ctrl + Alt + D)
                  </h3>
                  <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>
                    {tabDebugActiva === 'plsql'
                      ? payloadActual.procedimiento
                      : 'Diagnóstico y Prueba de Conexión en Vivo a Oracle Database'}
                  </p>
                </div>
              </div>
              <button type="button" className="close-btn" onClick={() => setMostrarModalDebug(false)}>
                <X size={20} />
              </button>
            </div>

            {/* Barra de Pestañas (Tabs) en la ventana de documentación */}
            <div
              style={{
                display: 'flex',
                gap: 8,
                padding: '10px 24px',
                background: '#f8fafc',
                borderBottom: '1px solid var(--border)'
              }}
            >
              <button
                type="button"
                onClick={() => setTabDebugActiva('plsql')}
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: 8,
                  padding: '8px 16px',
                  borderRadius: 8,
                  fontSize: '0.85rem',
                  fontWeight: 600,
                  cursor: 'pointer',
                  border: tabDebugActiva === 'plsql' ? '1px solid var(--primary)' : '1px solid var(--border)',
                  background: tabDebugActiva === 'plsql' ? 'var(--primary)' : 'white',
                  color: tabDebugActiva === 'plsql' ? 'white' : 'var(--text-main)',
                  transition: 'all 0.15s ease'
                }}
              >
                <Code2 size={16} />
                <span>Documentación PL/SQL</span>
              </button>

              <button
                type="button"
                onClick={() => {
                  setTabDebugActiva('conexion');
                  if (!resultadoConexion && !probandoConexion) {
                    probarConexionOracle();
                  }
                }}
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: 8,
                  padding: '8px 16px',
                  borderRadius: 8,
                  fontSize: '0.85rem',
                  fontWeight: 600,
                  cursor: 'pointer',
                  border: tabDebugActiva === 'conexion' ? '1px solid var(--primary)' : '1px solid var(--border)',
                  background: tabDebugActiva === 'conexion' ? 'var(--primary)' : 'white',
                  color: tabDebugActiva === 'conexion' ? 'white' : 'var(--text-main)',
                  transition: 'all 0.15s ease'
                }}
              >
                <Database size={16} />
                <span>Probar Conexión a Oracle</span>
              </button>
            </div>

            <div className="modal-body">
              {tabDebugActiva === 'plsql' ? (
                <>
                  {/* Selector de los 4 procedimientos PL/SQL que invoca el aplicativo */}
                  <div style={{ marginBottom: 18 }}>
                    <span
                      style={{
                        display: 'block',
                        fontSize: '0.8rem',
                        fontWeight: 700,
                        color: 'var(--text-muted)',
                        textTransform: 'uppercase',
                        letterSpacing: '0.03em',
                        marginBottom: 8
                      }}
                    >
                      Procedimientos de Base de Datos Invocados por la Aplicación:
                    </span>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                      {(
                        ['directorio', 'disponibilidad', 'filtros', 'sin_disponibilidad'] as const
                      ).map((procKey) => {
                        const item = catalogoProcedimientosPlsql[procKey];
                        const activo = procedimientoDebugSeleccionado === procKey;
                        return (
                          <button
                            key={procKey}
                            type="button"
                            onClick={() => setProcedimientoDebugSeleccionado(procKey)}
                            style={{
                              padding: '8px 14px',
                              borderRadius: 8,
                              fontSize: '0.82rem',
                              fontWeight: 600,
                              cursor: 'pointer',
                              border: activo ? '1.5px solid #0284c7' : '1px solid var(--border)',
                              background: activo ? '#e0f2fe' : 'white',
                              color: activo ? '#0369a1' : 'var(--text-main)',
                              transition: 'all 0.15s ease'
                            }}
                          >
                            {item.etiquetaCorta}
                          </button>
                        );
                      })}
                    </div>
                  </div>

                  {/* Cabecera y Explicación del Procedimiento Seleccionado */}
                  <div
                    style={{
                      marginBottom: 16,
                      padding: '12px 16px',
                      background: '#f8fafc',
                      borderRadius: 10,
                      border: '1px solid var(--border)'
                    }}
                  >
                    <div
                      style={{
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        flexWrap: 'wrap',
                        gap: 8,
                        marginBottom: 6
                      }}
                    >
                      <code style={{ fontSize: '0.92rem', fontWeight: 700, color: '#0284c7' }}>
                        {payloadActual.procedimiento}(p_json_entrada IN CLOB, p_json_salida OUT CLOB)
                      </code>
                      <span
                        style={{
                          fontSize: '0.75rem',
                          fontWeight: 700,
                          padding: '3px 10px',
                          borderRadius: 9999,
                          background: '#eef2ff',
                          color: '#4338ca',
                          border: '1px solid #c7d2fe'
                        }}
                      >
                        Endpoint: {payloadActual.endpointApi}
                      </span>
                    </div>
                    <p style={{ fontSize: '0.88rem', color: 'var(--text-main)', lineHeight: 1.5, margin: 0 }}>
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
                </>
              ) : (
                /* TAB 2: PROBAR CONEXIÓN A ORACLE DATABASE */
                <div>
                  <div
                    style={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center',
                      flexWrap: 'wrap',
                      gap: 12,
                      padding: '16px 20px',
                      background: resultadoConexion
                        ? resultadoConexion.conectado
                          ? '#ecfdf5'
                          : '#fef2f2'
                        : '#f8fafc',
                      border: `1.5px solid ${
                        resultadoConexion
                          ? resultadoConexion.conectado
                            ? '#6ee7b7'
                            : '#fecaca'
                          : '#e2e8f0'
                      }`,
                      borderRadius: 12,
                      marginBottom: 20
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                      {probandoConexion ? (
                        <RefreshCw size={24} style={{ color: 'var(--primary)' }} />
                      ) : resultadoConexion?.conectado ? (
                        <CheckCircle2 size={26} style={{ color: '#059669' }} />
                      ) : (
                        <AlertCircle size={26} style={{ color: resultadoConexion ? '#dc2626' : '#64748b' }} />
                      )}
                      <div>
                        <h4
                          style={{
                            fontSize: '1rem',
                            fontWeight: 700,
                            color: resultadoConexion
                              ? resultadoConexion.conectado
                                ? '#065f46'
                                : '#991b1b'
                              : '#0f172a'
                          }}
                        >
                          {probandoConexion
                            ? 'Verificando conexión con Oracle Database...'
                            : resultadoConexion
                            ? resultadoConexion.conectado
                              ? 'Conexión Exitosa a Oracle Database'
                              : `Error de Conexión (${resultadoConexion.codigo_oracle || 'Fallo'})`
                            : 'Listo para probar la conexión'}
                        </h4>
                        <p style={{ fontSize: '0.84rem', color: '#475569', marginTop: 2 }}>
                          {probandoConexion
                            ? 'Estableciendo sesión y consultando diccionario de datos...'
                            : resultadoConexion?.mensaje || 'Haga clic en el botón para ejecutar la prueba en tiempo real.'}
                        </p>
                      </div>
                    </div>

                    <button
                      type="button"
                      onClick={probarConexionOracle}
                      disabled={probandoConexion}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 8,
                        background: 'var(--primary)',
                        color: 'white',
                        border: 'none',
                        padding: '10px 18px',
                        borderRadius: 8,
                        fontSize: '0.85rem',
                        fontWeight: 600,
                        cursor: probandoConexion ? 'not-allowed' : 'pointer',
                        opacity: probandoConexion ? 0.65 : 1
                      }}
                    >
                      <RefreshCw size={15} />
                      <span>{probandoConexion ? 'Probando...' : 'Probar Conexión Ahora'}</span>
                    </button>
                  </div>

                  {/* Tarjetas de Configuración y Sesión */}
                  {resultadoConexion && (
                    <>
                      <div
                        style={{
                          display: 'grid',
                          gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
                          gap: 16,
                          marginBottom: 20
                        }}
                      >
                        {/* Parámetros .env.local */}
                        <div
                          style={{
                            background: 'white',
                            border: '1px solid var(--border)',
                            borderRadius: 10,
                            padding: 16
                          }}
                        >
                          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
                            <Server size={16} style={{ color: 'var(--primary)' }} />
                            <h5 style={{ fontSize: '0.9rem', fontWeight: 700 }}>
                              Parámetros Configurados (.env.local)
                            </h5>
                          </div>
                          <table className="debug-table" style={{ marginTop: 0 }}>
                            <tbody>
                              <tr>
                                <th>Usuario (ORACLE_DB_USER)</th>
                                <td>
                                  <code>{resultadoConexion.configuracion?.user || '-'}</code>
                                </td>
                              </tr>
                              <tr>
                                <th>Contraseña</th>
                                <td>
                                  <code>{resultadoConexion.configuracion?.password_masked || '****'}</code>
                                </td>
                              </tr>
                              <tr>
                                <th>Cadena de Conexión</th>
                                <td>
                                  <code>{resultadoConexion.configuracion?.connectString || '-'}</code>
                                </td>
                              </tr>
                              <tr>
                                <th>Modo Driver</th>
                                <td>{resultadoConexion.configuracion?.modo_driver || 'Thin'}</td>
                              </tr>
                              <tr>
                                <th>Latencia Total</th>
                                <td>
                                  <strong>{resultadoConexion.latencia_total_ms ?? '-'} ms</strong>
                                  {resultadoConexion.latencia_conexion_ms !== undefined && (
                                    <span style={{ color: 'var(--text-muted)', fontSize: '0.78rem', marginLeft: 6 }}>
                                      (Handshake: {resultadoConexion.latencia_conexion_ms} ms)
                                    </span>
                                  )}
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>

                        {/* Datos de la Sesión en Oracle */}
                        {resultadoConexion.conectado && resultadoConexion.sesion && (
                          <div
                            style={{
                              background: 'white',
                              border: '1px solid var(--border)',
                              borderRadius: 10,
                              padding: 16
                            }}
                          >
                            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
                              <Database size={16} style={{ color: '#059669' }} />
                              <h5 style={{ fontSize: '0.9rem', fontWeight: 700 }}>
                                Sesión Activa en el Servidor Oracle
                              </h5>
                            </div>
                            <table className="debug-table" style={{ marginTop: 0 }}>
                              <tbody>
                                <tr>
                                  <th>Esquema Conectado</th>
                                  <td>
                                    <code style={{ color: '#059669', background: '#ecfdf5' }}>
                                      {resultadoConexion.sesion.usuario_actual}
                                    </code>
                                  </td>
                                </tr>
                                <tr>
                                  <th>Base de Datos / PDB</th>
                                  <td>
                                    <strong>{resultadoConexion.sesion.db_name}</strong> /{' '}
                                    <code>{resultadoConexion.sesion.con_name}</code>
                                  </td>
                                </tr>
                                <tr>
                                  <th>Instancia / Host</th>
                                  <td>
                                    {resultadoConexion.sesion.instance_name} ({resultadoConexion.sesion.server_host})
                                  </td>
                                </tr>
                                <tr>
                                  <th>Fecha/Hora Servidor (Bogotá)</th>
                                  <td>{resultadoConexion.sesion.fecha_servidor}</td>
                                </tr>
                                <tr>
                                  <th>Filas en TKR_DISPONIBILIDAD_BITMAP</th>
                                  <td>
                                    <strong>
                                      {resultadoConexion.total_registros_bitmap >= 0
                                        ? resultadoConexion.total_registros_bitmap.toLocaleString()
                                        : 'Tabla no encontrada'}
                                    </strong>
                                  </td>
                                </tr>
                              </tbody>
                            </table>
                          </div>
                        )}
                      </div>

                      {/* Estado de Objetos PL/SQL en el esquema */}
                      {resultadoConexion.conectado && Array.isArray(resultadoConexion.objetos_bd) && (
                        <div>
                          <h5 style={{ fontSize: '0.92rem', fontWeight: 700, marginBottom: 8 }}>
                            Estado de Paquetes y Tablas del Directorio en {resultadoConexion.sesion?.usuario_actual}:
                          </h5>
                          <div style={{ overflowX: 'auto' }}>
                            <table className="debug-table">
                              <thead>
                                <tr>
                                  <th>Objeto Oracle</th>
                                  <th>Tipo</th>
                                  <th>Estado</th>
                                  <th>Última Compilación (DDL)</th>
                                </tr>
                              </thead>
                              <tbody>
                                {resultadoConexion.objetos_bd.length === 0 ? (
                                  <tr>
                                    <td colSpan={4} style={{ textAlign: 'center', color: 'var(--text-muted)' }}>
                                      No se encontraron los objetos del directorio en este esquema.
                                    </td>
                                  </tr>
                                ) : (
                                  resultadoConexion.objetos_bd.map((obj: any, i: number) => (
                                    <tr key={i}>
                                      <td>
                                        <code>{obj.nombre}</code>
                                      </td>
                                      <td>{obj.tipo}</td>
                                      <td>
                                        <span
                                          style={{
                                            display: 'inline-block',
                                            padding: '2px 8px',
                                            borderRadius: 6,
                                            fontSize: '0.75rem',
                                            fontWeight: 700,
                                            background: obj.estado === 'VALID' ? '#dcfce7' : '#fee2e2',
                                            color: obj.estado === 'VALID' ? '#166534' : '#991b1b'
                                          }}
                                        >
                                          {obj.estado}
                                        </span>
                                      </td>
                                      <td>{obj.ultima_compilacion}</td>
                                    </tr>
                                  ))
                                )}
                              </tbody>
                            </table>
                          </div>
                        </div>
                      )}
                    </>
                  )}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Modal: Profesionales Sin Disponibilidad */}
      {mostrarModalSinDisp && (
        <div className="modal-overlay" onClick={() => setMostrarModalSinDisp(false)}>
          <div
            className="modal-sin-disp-container"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div className="modal-header">
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <div style={{ width: 44, height: 44, borderRadius: 12, background: '#fff1f2', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#e11d48', border: '1px solid #fecdd3' }}>
                  <CalendarX size={24} />
                </div>
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
                    <h2 style={{ fontSize: '1.2rem', fontWeight: 700, color: '#0f172a' }}>
                      Especialidades y Profesionales Sin Disponibilidad
                    </h2>
                    {datosSinDisp && !cargandoSinDisp && (
                      <span className="sin-disp-header-badge">
                        <Layers size={13} />
                        {datosSinDisp.total_sin_disponibilidad} especialidades
                      </span>
                    )}
                  </div>
                  <p style={{ fontSize: '0.82rem', color: 'var(--text-muted)', marginTop: 2 }}>
                    Rango evaluado: <strong>{fechaInicio}</strong> al <strong>{fechaFin}</strong>
                  </p>
                </div>
              </div>
              <button
                type="button"
                className="close-btn"
                onClick={() => setMostrarModalSinDisp(false)}
                title="Cerrar modal"
              >
                <X size={22} />
              </button>
            </div>

            {/* Toolbar con buscador, pestañas de filtro y exportación */}
            <div className="sin-disp-toolbar">
              <div className="sin-disp-search-box">
                <Search size={15} style={{ position: 'absolute', left: 12, top: 11, color: 'var(--text-muted)' }} />
                <input
                  type="text"
                  className="form-control"
                  style={{ height: 38, paddingLeft: 36, fontSize: '0.85rem' }}
                  placeholder="Buscar especialidad o médico..."
                  value={busquedaSinDisp}
                  onChange={(e) => setBusquedaSinDisp(e.target.value)}
                />
              </div>

              {/* Pestañas de filtrado rápido */}
              <div className="sin-disp-tabs-filter">
                <button
                  type="button"
                  className={`sin-disp-tab-btn ${filtroTipoSinDisp === 'TODAS' ? 'active' : ''}`}
                  onClick={() => setFiltroTipoSinDisp('TODAS')}
                >
                  Todas ({datosSinDisp?.total_sin_disponibilidad || 0})
                </button>
                <button
                  type="button"
                  className={`sin-disp-tab-btn ${filtroTipoSinDisp === 'SIN_MEDICOS' ? 'active' : ''}`}
                  onClick={() => setFiltroTipoSinDisp('SIN_MEDICOS')}
                >
                  Sin médicos ({datosSinDisp?.total_especialidades_sin_medicos || 0})
                </button>
                <button
                  type="button"
                  className={`sin-disp-tab-btn ${filtroTipoSinDisp === 'CON_MEDICOS' ? 'active' : ''}`}
                  onClick={() => setFiltroTipoSinDisp('CON_MEDICOS')}
                >
                  Con médicos sin cupos ({((datosSinDisp?.total_sin_disponibilidad || 0) - (datosSinDisp?.total_especialidades_sin_medicos || 0))})
                </button>
              </div>

              {/* Botón Exportar a Excel */}
              <button
                type="button"
                className="btn-export-excel"
                onClick={exportarExcelSinDisponibilidad}
                disabled={cargandoSinDisp || !datosSinDisp || datosSinDisp.total_sin_disponibilidad === 0}
                title="Descargar listado completo en formato Excel (.xlsx)"
              >
                <FileSpreadsheet size={16} />
                <span>Exportar a Excel</span>
              </button>
            </div>

            {/* Contenido / Listado por Especialidad */}
            <div className="sin-disp-content-scroll">
              {cargandoSinDisp ? (
                <div style={{ textAlign: 'center', padding: '60px 0' }}>
                  <div className="spinner" style={{ margin: '0 auto 14px auto' }} />
                  <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem', fontWeight: 500 }}>
                    Consultando todas las especialidades y evaluando disponibilidad en el rango...
                  </p>
                </div>
              ) : !datosSinDisp?.especialidades || datosSinDisp.especialidades.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '50px 0', background: '#f8fafc', borderRadius: 12, border: '1px solid #e2e8f0' }}>
                  <Check size={36} style={{ color: '#059669', margin: '0 auto 10px auto' }} />
                  <h4 style={{ fontSize: '1rem', fontWeight: 600, color: '#0f172a' }}>
                    ¡No hay especialidades sin disponibilidad!
                  </h4>
                  <p style={{ color: 'var(--text-muted)', fontSize: '0.85rem', marginTop: 4 }}>
                    Todas las especialidades cuentan con médicos con cupos libres para el rango.
                  </p>
                </div>
              ) : especialidadesFiltradasSinDisp.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '50px 0' }}>
                  <AlertCircle size={32} style={{ color: 'var(--text-muted)', margin: '0 auto 8px auto' }} />
                  <p style={{ color: 'var(--text-muted)', fontSize: '0.88rem' }}>
                    No hay especialidades que coincidan con &ldquo;{busquedaSinDisp}&rdquo; en esta pestaña.
                  </p>
                </div>
              ) : (
                <>
                  {/* Barra de control para acordeón si hay especialidades con médicos */}
                  {especialidadesFiltradasSinDisp.some(e => e.tiene_profesionales && e.profesionales?.length > 0) && (
                    <div className="sin-disp-expand-controls">
                      <span style={{ fontSize: '0.82rem', color: '#64748b', fontWeight: 600 }}>
                        Especialidades con médicos ({especialidadesFiltradasSinDisp.filter(e => e.tiene_profesionales && e.profesionales?.length > 0).length}):
                      </span>
                      <div style={{ display: 'flex', gap: 8 }}>
                        <button
                          type="button"
                          className="btn-link-action"
                          onClick={expandirTodas}
                        >
                          Expandir todas
                        </button>
                        <span style={{ color: '#cbd5e1' }}>|</span>
                        <button
                          type="button"
                          className="btn-link-action"
                          onClick={contraerTodas}
                        >
                          Contraer todas
                        </button>
                      </div>
                    </div>
                  )}

                  {/* 1. Especialidades CON MÉDICOS SIN CUPOS (Acordeón interactivo) */}
                  {especialidadesFiltradasSinDisp
                    .filter((e) => e.tiene_profesionales && e.profesionales && e.profesionales.length > 0)
                    .map((esp) => {
                      const estaExpandida = !especialidadesContraidas.has(esp.id_especialidad);

                      return (
                        <div key={esp.id_especialidad} className="sin-disp-spec-card">
                          {/* Header Acordeón Clickeable */}
                          <div
                            className="sin-disp-spec-header accordion-header"
                            onClick={() => toggleEspecialidad(esp.id_especialidad)}
                            title="Haga clic para expandir o contraer esta especialidad"
                          >
                            <div className="sin-disp-spec-title">
                              <Stethoscope size={18} style={{ color: '#0284c7' }} />
                              <span>{esp.nombre_especialidad}</span>
                            </div>

                            <div className="sin-disp-spec-right-actions">
                              <span className="sin-disp-spec-count">
                                {esp.profesionales.length} {esp.profesionales.length === 1 ? 'médico sin cupos' : 'médicos sin cupos'}
                              </span>
                              <div className={`accordion-arrow ${estaExpandida ? 'rotated' : ''}`}>
                                <ChevronDown size={18} />
                              </div>
                            </div>
                          </div>

                          {/* Lista de Médicos (Se muestra solo si está expandida) */}
                          {estaExpandida && (
                            <div className="sin-disp-doc-list">
                              {esp.profesionales.map((doc) => {
                                const iniciales = (doc.nombre_completo || 'Dr')
                                  .split(' ')
                                  .map((n) => n[0])
                                  .slice(0, 2)
                                  .join('')
                                  .toUpperCase();

                                const dias = (() => {
                                  const raw = doc.days_of_service;
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
                                    return trimmed.split(',').map((d) => d.trim()).filter(Boolean);
                                  }
                                  return [];
                                })();

                                return (
                                  <div key={doc.id_usuario} className="sin-disp-doc-row">
                                    <div className="sin-disp-doc-avatar">
                                      {iniciales}
                                    </div>
                                    <div className="sin-disp-doc-info">
                                      <div className="sin-disp-doc-name">
                                        <span>{doc.nombre_completo}</span>
                                        <span style={{ fontSize: '0.74rem', color: '#64748b', fontWeight: 400 }}>
                                          (ID: {doc.id_usuario})
                                        </span>
                                      </div>

                                      {/* Días de atención */}
                                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, margin: '3px 0', flexWrap: 'wrap' }}>
                                        <span style={{ fontSize: '0.72rem', color: '#64748b', fontWeight: 600 }}>
                                          Días de atención habitual:
                                        </span>
                                        {dias.length > 0 ? (
                                          dias.map((d, idx) => (
                                            <span key={idx} className="badge-day-pill" style={{ height: 18, minWidth: 22, fontSize: '0.68rem', padding: '0 4px' }}>
                                              {d}
                                            </span>
                                          ))
                                        ) : (
                                          <span style={{ fontSize: '0.72rem', color: '#94a3b8', fontStyle: 'italic' }}>
                                            Sin horarios configurados
                                          </span>
                                        )}
                                      </div>

                                      {/* Contacto */}
                                      <div className="sin-disp-doc-contact">
                                        {doc.correo && (
                                          <span className="sin-disp-doc-contact-item">
                                            <Mail size={12} />
                                            {doc.correo}
                                          </span>
                                        )}
                                        {doc.telefono && (
                                          <span className="sin-disp-doc-contact-item">
                                            <Phone size={12} />
                                            {doc.telefono}
                                          </span>
                                        )}
                                      </div>
                                    </div>

                                    <div>
                                      <span className="sin-disp-doc-badge-status">
                                        <CalendarX size={12} />
                                        0 cupos disponibles
                                      </span>
                                    </div>
                                  </div>
                                );
                              })}
                            </div>
                          )}
                        </div>
                      );
                    })}

                  {/* 2. Especialidades SIN MÉDICOS (Cuadrícula limpia y compacta, sin rayas) */}
                  {especialidadesFiltradasSinDisp.some(e => !e.tiene_profesionales || !e.profesionales || e.profesionales.length === 0) && (
                    <div style={{ marginTop: 10, flexShrink: 0 }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
                        <UserX size={16} style={{ color: '#64748b' }} />
                        <span style={{ fontSize: '0.85rem', fontWeight: 700, color: '#334155' }}>
                          Especialidades sin profesionales asignados ({especialidadesFiltradasSinDisp.filter(e => !e.tiene_profesionales || !e.profesionales || e.profesionales.length === 0).length}):
                        </span>
                      </div>

                      <div className="sin-disp-grid-empty">
                        {especialidadesFiltradasSinDisp
                          .filter((e) => !e.tiene_profesionales || !e.profesionales || e.profesionales.length === 0)
                          .map((esp) => (
                            <div key={esp.id_especialidad} className="sin-disp-empty-card">
                              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                                <Stethoscope size={15} style={{ color: '#94a3b8', flexShrink: 0 }} />
                                <span style={{ fontSize: '0.84rem', color: '#1e293b', fontWeight: 600 }}>
                                  {esp.nombre_especialidad}
                                </span>
                              </div>
                              <span className="sin-disp-spec-count empty-badge" style={{ fontSize: '0.7rem', padding: '2px 8px' }}>
                                Sin médicos
                              </span>
                            </div>
                          ))}
                      </div>
                    </div>
                  )}
                </>
              )}
            </div>
          </div>
        </div>
      )}
</div>
  );
}
