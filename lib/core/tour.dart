import 'queue_controller.dart';
import 'visit.dart';

/// One step of the first-run tour. Script from the Turn 3 table of
/// `design/Widget Redesign.dc.html`; each step drives the live panel to the
/// [size] and reveal state it talks about.
class TourStep {
  const TourStep(this.label, this.title, this.body,
      {this.size = WidgetSize.small,
      this.open = false,
      this.done = false,
      this.highlight,
      this.face});

  final String label;
  final String title;
  final String body;
  final WidgetSize size;
  final bool open;
  final bool done;

  /// The panel region ringed while this step shows.
  final TourRegion? highlight;

  /// The action face shown while this step shows. Display only: actions never
  /// fire during the tour.
  final VisitAction? face;
}

/// Step 7 differs from the prototype: the backend only ends a visit that is
/// serving, so the widget shows START between ALERT and END VISIT.
const tourSteps = <TourStep>[
  TourStep('Widget', 'Widget ini sentiasa di atas',
      'Ia melekat di sudut skrin anda, di atas sistem hospital. Tiada apa perlu dibuka, tiada skrin perlu ditukar.'),
  TourStep('Baris utama', 'Baris ini pesakit seterusnya',
      'Bukan yang sedang di dalam bilik. Nama dipendekkan, dan di sebelahnya kedudukan dia dalam sesi hari ini — ketiga daripada sepuluh.',
      highlight: TourRegion.next),
  TourStep('Dua nombor', 'Pukul berapa, dan berapa lama menunggu',
      'Kiri: waktu temu janji dia. Kanan: sudah berapa minit dia menunggu. Beza antara dua ini kelewatan anda.',
      highlight: TourRegion.next),
  TourStep('Garis bawah', 'Garis bawah itu penantian dia',
      'Hijau selagi penantian bawah 20 minit. Merah setiap minit selepas itu. Jika merahnya panjang, ada masalah.',
      highlight: TourRegion.meter),
  TourStep('NOW', 'Hala kursor ke panel untuk lihat NOW',
      'Pesakit yang sedang diperiksa: nama penuh, token, dan sudah berapa minit dia di dalam bilik. Garis di bawahnya mengikut tempoh konsultasi lalai klinik anda — hijau selagi dalam tempoh, merah selepas itu.',
      open: true,
      highlight: TourRegion.now),
  TourStep('Alert', 'Alert memanggil pesakit seterusnya',
      'Tekan sekali sahaja. Loceng berbunyi tanda WhatsApp sudah dihantar. Tiada notifikasi lain perlu ditutup.',
      highlight: TourRegion.act, face: VisitAction.alert),
  TourStep('Start, End Visit', 'Selepas itu Start, kemudian End Visit',
      'Apabila pesakit masuk, tekan Start. Selepas konsultasi, tekan End Visit untuk tamatkan lawatan dan naikkan queue. Baris tadi mula kira minit sejak dipanggil — hijau sehingga lima minit, selepas itu merah.',
      highlight: TourRegion.act, face: VisitAction.start),
  TourStep('No-Show', 'No-Show apabila pesakit tidak muncul',
      'Ia tersembunyi dalam reveal, bukan di depan. Tahan butang, jangan ketik — sekali tertekan tiada undo.',
      open: true,
      highlight: TourRegion.noShow),
  TourStep('Senarai', 'Medium dan Large tunjuk senarai',
      'Empat orang seterusnya, atau seluruh sesi. Setiap baris: waktu temu janji, token, nama penuh, minit menunggu. Yang merah sudah menunggu lebih 20 minit.',
      size: WidgetSize.large,
      highlight: TourRegion.list),
  TourStep('Kawalan', 'Lima kawalan dalam reveal',
      'Grip untuk mengalihkan widget, anak panah untuk buka queue penuh dalam Chup, kemudian saiz dan Help, Sign out, minimise, close. Minimise mengecilkan widget kepada satu nombor; close meninggalkan tab nipis di tepi skrin — klik untuk buka semula.',
      size: WidgetSize.large, open: true,
      highlight: TourRegion.controls),
  TourStep('Selepas itu', 'Itu sahaja',
      'Tiga baris ini muncul sendiri apabila perlu: reading the queue semasa mula-mula dibuka, no one in the queue apabila sesi sudah habis, dan cannot reach Chup jika sambungan terputus.',
      size: WidgetSize.large, done: true),
];

/// Regions of the panel a tour step can ring.
enum TourRegion { next, meter, now, act, noShow, list, controls }

/// The card sits beside the panel, never over it.
const double kTourCardWidth = 236;
/// Two lines above what steps 7 and 10 need in Arial, since Segoe UI sets wider.
const double kTourCardHeight = 224;
const double kTourGap = 12;
