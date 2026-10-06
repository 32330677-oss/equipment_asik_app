import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/lookups.dart';
import '../../widgets/ui.dart';

/// Create / edit a rate card of one machine, with a live "Test this price" calculator.
/// Returns true when saved.
class RateCardFormScreen extends StatefulWidget {
  const RateCardFormScreen({super.key, required this.machine, this.card, this.copyFrom, this.revise});
  final Json machine;
  final Json? card;
  final Json? copyFrom;
  /// Change this card FROM A DATE: the card is closed the day before and a new one starts (history kept).
  final Json? revise;

  static Future<bool?> open(BuildContext context, {required Json machine, Json? card, Json? copyFrom, Json? revise}) =>
      Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RateCardFormScreen(machine: machine, card: card, copyFrom: copyFrom, revise: revise)));

  @override
  State<RateCardFormScreen> createState() => _RateCardFormScreenState();
}

class _SampleRow {
  _SampleRow(this.status, {double gross = 10, double brk = 1, double breakdown = 0, double standby = 0})
      : gross = TextEditingController(text: _h(gross)),
        brk = TextEditingController(text: _h(brk)),
        breakdown = TextEditingController(text: _h(breakdown)),
        standby = TextEditingController(text: _h(standby));
  String status;
  final TextEditingController gross;
  final TextEditingController brk;
  final TextEditingController breakdown;
  final TextEditingController standby;
  static String _h(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

class _RateCardFormScreenState extends State<RateCardFormScreen> {
  final _form = GlobalKey<FormState>();
  PickOption? _contract;
  late String _from;
  String? _to;
  String _mode = 'Hourly';
  final _hourly = TextEditingController();
  final _daily = TextEditingController();
  final _monthly = TextEditingController();
  final _stdHours = TextEditingController(text: '8');
  bool _ot = false;
  final _otThreshold = TextEditingController();
  final _otRate = TextEditingController();
  final _otMult = TextEditingController(text: '1');
  final _standbyPct = TextEditingController(text: '50');
  final _breakdownPct = TextEditingController(text: '0');
  String _breakPolicy = 'Deduct';
  String _partial = 'ProRata';
  final _halfDay = TextEditingController();
  final _secondShift = TextEditingController(text: '0');
  String _fuel = 'VendorSupplies';
  final _notes = TextEditingController();
  bool _saving = false;

  // test panel
  final List<_SampleRow> _rows = [
    _SampleRow('Working', gross: 10, brk: 1),
    _SampleRow('Working', gross: 8, brk: 1, breakdown: 2),
    _SampleRow('Standby', gross: 0, brk: 0),
  ];
  final _testMonth = TextEditingController(text: Fmt.thisMonth());
  final _holidayDays = TextEditingController(text: '0');
  final _fuelLiters = TextEditingController();
  final _fuelPrice = TextEditingController();
  Json? _result;
  String? _testError;
  bool _testing = false;

  bool get _editing => widget.card != null;
  bool get _revising => widget.revise != null;

  @override
  void initState() {
    super.initState();
    _from = Fmt.today();
    final c = widget.card ?? widget.revise ?? widget.copyFrom;
    if (c != null) {
      String t(String k) => c.strOrNull(k) == null ? '' : _trim(c.str(k));
      _contract = PickOption(c.intv('vendor_contract_id'), '${c.str('contract_number')}  (${c.str('currency')})');
      if (widget.card != null) {
        _from = c.str('effective_from');
        _to = c.strOrNull('effective_to');
      }
      if (widget.revise != null) {
        final start = c.str('effective_from');
        final today = Fmt.today();
        _from = today.compareTo(start) > 0 ? today : Fmt.dateOf(Fmt.parse(start)!.add(const Duration(days: 1)));
      }
      _mode = c.str('billing_mode', 'Hourly');
      _hourly.text = t('hourly_rate');
      _daily.text = t('daily_rate');
      _monthly.text = t('monthly_rate');
      _stdHours.text = t('standard_hours_per_day');
      _ot = c.flag('overtime_enabled');
      _otThreshold.text = t('overtime_threshold_hours');
      _otRate.text = t('overtime_rate');
      _otMult.text = t('overtime_multiplier');
      _standbyPct.text = t('standby_billable_pct');
      _breakdownPct.text = t('breakdown_billable_pct');
      _breakPolicy = c.str('break_policy', 'Deduct');
      _partial = c.str('daily_partial_rule', 'ProRata');
      _halfDay.text = t('half_day_threshold_hours');
      _secondShift.text = t('second_shift_pct').isEmpty ? '0' : t('second_shift_pct');
      _fuel = c.str('fuel_policy', 'VendorSupplies');
      _notes.text = c.str('notes');
    }
    if (_contract == null) _autoContract();
  }

  /// New card: pick the vendor's contract automatically when there is exactly one.
  Future<void> _autoContract() async {
    try {
      final list = await Lookups.contracts(widget.machine.intv('vendor_id'));
      if (mounted && _contract == null && list.length == 1) setState(() => _contract = list.first);
    } catch (_) {}
  }

  Future<List<PickOption>> _contractOptions() async {
    final list = await Lookups.contracts(widget.machine.intv('vendor_id'));
    return [...list, PickOption('__new', '+ New contract for ${widget.machine.str('vendor_name')}', list.isEmpty ? 'This vendor has no contract yet' : null)];
  }

  /// Quick contract creation without leaving the rate card.
  Future<void> _newContract() async {
    final number = TextEditingController();
    var start = _from;
    var currency = 'USD';
    final created = await showFormDialog<Json>(
      context,
      title: 'New contract - ${widget.machine.str('vendor_name')}',
      width: 460,
      onSave: () async => asJson(await Api.I.post('/equipment/vendors/${widget.machine.intv('vendor_id')}/contracts', {
        'contract_number': number.text.trim(), 'start_date': start, 'currency': currency, 'status': 'Active',
      })),
      body: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        textField(number, 'Contract number', required: true, hint: 'e.g. C-2026-001'),
        const SizedBox(height: 12),
        DateField(label: 'Contract start', value: start, onChanged: (v) => set(() => start = v ?? start)),
        const SizedBox(height: 12),
        Dropdown<String>(label: 'Currency', value: currency, width: null, items: const [
          DropdownMenuItem(value: 'USD', child: Text('USD')),
          DropdownMenuItem(value: 'SYP', child: Text('SYP')),
          DropdownMenuItem(value: 'EUR', child: Text('EUR')),
        ], onChanged: (v) => set(() => currency = v ?? currency)),
      ]),
    );
    if (created == null || !mounted) return;
    setState(() {
      _contract = PickOption(created.intv('vendor_contract_id'), '${created.str('contract_number')}  (${created.str('currency')})');
      if (created.str('start_date').compareTo(_from) > 0) _from = created.str('start_date');
    });
    showSnack(context, 'Contract created.');
  }

  static String _trim(String s) {
    if (!s.contains('.')) return s;
    var r = s.replaceAll(RegExp(r'0+$'), '');
    if (r.endsWith('.')) r = r.substring(0, r.length - 1);
    return r;
  }

  Map<String, dynamic> _card() {
    final m = <String, dynamic>{
      'billing_mode': _mode,
      'hourly_rate': _mode == 'Hourly' ? numOrNull(_hourly) : null,
      'daily_rate': _mode == 'Daily' ? numOrNull(_daily) : null,
      'monthly_rate': _mode == 'Monthly' ? numOrNull(_monthly) : null,
      'standard_hours_per_day': numOrNull(_stdHours),
      // no minimum billable hours: not used by the company (an old value is cleared when the card is saved)
      'min_billable_hours_per_day': null,
      // Monthly: overtime is always counted (hours above the hours due), at the month's hourly price unless a price is typed.
      'overtime_enabled': _mode == 'Monthly' ? true : _ot,
      'overtime_threshold_hours': _mode != 'Monthly' && _ot ? numOrNull(_otThreshold) : null,
      'overtime_rate': _mode == 'Monthly' || _ot ? numOrNull(_otRate) : null,
      'overtime_multiplier': _mode != 'Monthly' && _ot ? numOrNull(_otMult) : null,
      'standby_billable_pct': numOrNull(_standbyPct),
      'breakdown_billable_pct': numOrNull(_breakdownPct),
      'break_policy': _breakPolicy,
      'daily_partial_rule': _mode == 'Daily' ? _partial : null,
      'half_day_threshold_hours': _mode == 'Daily' && _partial == 'HalfDayThreshold' ? numOrNull(_halfDay) : null,
      // a second shift the same day (Daily only): work above one day billed at this % of the daily price
      'second_shift_pct': _mode == 'Daily' ? (numOrNull(_secondShift) ?? 0) : 0,
      // the operator is the vendor's business: never priced by us
      'operator_included': true,
      'operator_daily_rate': null,
      'fuel_policy': _fuel,
      'notes': textOrNull(_notes),
    };
    // On edit, nullable fields are sent as null so an old value is cleared; required ones fall back to the stored value.
    const nullable = {'hourly_rate', 'daily_rate', 'monthly_rate', 'min_billable_hours_per_day', 'overtime_threshold_hours', 'overtime_rate',
      'half_day_threshold_hours', 'operator_daily_rate', 'notes'};
    m.removeWhere((k, v) => v == null && !((_editing || _revising) && nullable.contains(k)));
    return m;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_contract == null && !_revising) {
      showSnack(context, 'Choose the vendor contract.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      if (_revising) {
        await Api.I.post('/equipment/rate-cards/${widget.revise!.intv('rate_card_id')}/revise', {..._card(), 'effective_from': _from});
        if (!mounted) return;
        showSnack(context, 'New prices apply from ${Fmt.date(_from)}. The previous card ends the day before.');
        Navigator.pop(context, true);
        return;
      }
      final body = {..._card(), 'vendor_contract_id': _contract!.value, 'effective_from': _from, if (_to != null) 'effective_to': _to};
      if (_editing) {
        try {
          await Api.I.put('/equipment/rate-cards/${widget.card!.intv('rate_card_id')}', body);
        } on ApiException catch (e) {
          // a draft payroll batch uses this card: the change needs a reason (the batch must then be regenerated)
          final fields = e.details?.obj('fields') ?? <String, dynamic>{};
          if (e.code != 'VALIDATION_ERROR' || !fields.containsKey('reason') || !mounted) rethrow;
          final reason = await promptText(context, 'Why does this rate card change?',
              label: 'Reason (kept in the history)', minLength: 5, help: '${fields['reason']}');
          if (reason == null) {
            if (mounted) setState(() => _saving = false);
            return;
          }
          await Api.I.put('/equipment/rate-cards/${widget.card!.intv('rate_card_id')}', {...body, 'reason': reason});
        }
      } else {
        await Api.I.post('/equipment/machines/${widget.machine.intv('equipment_id')}/rate-cards', body);
      }
      if (!mounted) return;
      showSnack(context, 'Rate card saved.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  Future<void> _test() async {
    setState(() { _testing = true; _testError = null; });
    try {
      final liters = numOrNull(_fuelLiters);
      final r = await Api.I.post('/equipment/rate-cards/preview', {
        'rate_card': _card()..removeWhere((k, v) => v == null),
        'sample_rows': [
          for (final s in _rows)
            {
              'day_status': s.status,
              'gross_hours': s.status == 'Absent' || s.status == 'Holiday' ? null : numOrNull(s.gross),
              'break_hours': s.status == 'Working' ? numOrNull(s.brk) : null,
              'breakdown_hours': s.status == 'Working' ? numOrNull(s.breakdown) : null,
              'standby_hours': s.status == 'Working' ? numOrNull(s.standby) : null,
            }..removeWhere((k, v) => v == null),
        ],
        'month': _testMonth.text.trim(),
        'holiday_days': numOrNull(_holidayDays),
        if (liters != null && liters > 0) 'fuel': [{'liters': liters, 'price_per_liter': numOrNull(_fuelPrice) ?? 0}],
      });
      if (!mounted) return;
      setState(() => _result = asJson(r));
    } catch (e) {
      if (!mounted) return;
      setState(() { _result = null; _testError = e is ApiException ? e.message : '$e'; });
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.machine;
    final wide = MediaQuery.of(context).size.width >= 1100;
    final form = _formCard(m);
    final test = _testCard();
    return Scaffold(
      appBar: AppBar(
        title: Text('${_revising ? 'Change prices from a date' : _editing ? 'Correct rate card' : 'New rate card'} - ${m.str('equipment_code')}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 6, child: ListView(padding: const EdgeInsets.all(20), children: [form])),
                Expanded(flex: 5, child: ListView(padding: const EdgeInsets.fromLTRB(0, 20, 20, 20), children: [test])),
              ])
            : ListView(padding: const EdgeInsets.all(16), children: [form, const SizedBox(height: 16), test]),
      ),
    );
  }

  Widget _section(String title, List<Widget> children, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _formCard(Json m) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _section('Contract and period', [
            FormGrid(children: [
              PickerField(
                label: 'Vendor contract *',
                valueLabel: _contract?.label,
                icon: Icons.description_rounded,
                clearable: false,
                enabled: !_revising && (!_editing || !(widget.card?.flag('used_in_finalized_payroll') ?? false)),
                load: _contractOptions,
                onChanged: (v) {
                  if (v?.value == '__new') {
                    _newContract();
                  } else {
                    setState(() => _contract = v);
                  }
                },
              ),
              const SizedBox(),
              DateField(label: _revising ? 'New prices apply from *' : 'Effective from *', value: _from, onChanged: (v) => setState(() => _from = v ?? _from)),
              if (!_revising) DateField(label: 'Effective to (open)', value: _to, clearable: true, onChanged: (v) => setState(() => _to = v)),
            ]),
          ], hint: _revising ? 'The current card stays as it is until the day before; invoices already issued keep their prices.' : null),
          _section('Billing', [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Hourly', icon: Icon(Icons.timer_rounded), label: Text('Hourly')),
                ButtonSegment(value: 'Daily', icon: Icon(Icons.today_rounded), label: Text('Daily')),
                ButtonSegment(value: 'Monthly', icon: Icon(Icons.calendar_month_rounded), label: Text('Monthly')),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
            const SizedBox(height: 12),
            FormGrid(children: [
              if (_mode == 'Hourly') textField(_hourly, 'Price per hour', number: true, required: true),
              if (_mode == 'Daily') textField(_daily, 'Price per day', number: true, required: true),
              if (_mode == 'Monthly') textField(_monthly, 'Price per month', number: true, required: true),
              textField(_stdHours, _mode == 'Monthly' ? 'Working hours per day at the site' : 'Standard hours per day', number: true, required: true, suffix: 'h'),
              if (_mode == 'Monthly') textField(_otRate, 'Overtime price per hour', number: true, hint: 'empty = the hourly price of the month'),
              if (_mode == 'Daily')
                Dropdown<String>(label: 'Partial day', value: _partial, width: null, items: const [
                  DropdownMenuItem(value: 'ProRata', child: Text('Pro rata of the hours')),
                  DropdownMenuItem(value: 'FullDayIfWorked', child: Text('Full day if it worked')),
                  DropdownMenuItem(value: 'HalfDayThreshold', child: Text('Half day under a threshold')),
                ], onChanged: (v) => setState(() => _partial = v ?? _partial)),
              if (_mode == 'Daily' && _partial == 'HalfDayThreshold') textField(_halfDay, 'Half-day threshold', number: true, required: true, suffix: 'h'),
              if (_mode == 'Daily')
                textField(_secondShift, 'Second shift same day', number: true, suffix: '%', hint: '0 to 100 of the daily price (0 = not paid)'),
            ]),
          ], hint: _mode == 'Monthly'
              ? 'Working days of a month = days of the month minus Fridays. Hourly price = monthly price / working days / hours per day. '
                  'Hours due = working days x hours per day. All hours done = full month; more = overtime; fewer = missing hours deducted.'
              : null),
          if (_mode != 'Monthly') _section('Overtime', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _ot,
              onChanged: (v) => setState(() => _ot = v),
              title: const Text('Pay overtime'),
              subtitle: const Text('Hours above the threshold are paid at the overtime price'),
            ),
            if (_ot)
              FormGrid(columns: 3, children: [
                textField(_otThreshold, 'Threshold', number: true, suffix: 'h', hint: 'standard hours'),
                textField(_otRate, 'Overtime price / h', number: true, hint: 'or use multiplier'),
                textField(_otMult, 'Multiplier', number: true, suffix: '×'),
              ]),
          ]),
          _section('Standby, breakdown and breaks', [
            FormGrid(children: [
              // monthly machines: no standby %; the accountant gives the standby hours on each row (Attendance review)
              if (_mode != 'Monthly') textField(_standbyPct, 'Standby billable', number: true, required: true, suffix: '%'),
              textField(_breakdownPct, 'Breakdown billable', number: true, required: true, suffix: '%'),
              Dropdown<String>(label: 'Breaks', value: _breakPolicy, width: null, items: const [
                DropdownMenuItem(value: 'Deduct', child: Text('Deducted from hours')),
                DropdownMenuItem(value: 'Paid', child: Text('Paid (not deducted)')),
              ], onChanged: (v) => setState(() => _breakPolicy = v ?? _breakPolicy)),
            ]),
          ], hint: _mode == 'Monthly'
              ? 'Standby of a monthly machine: no %. On each standby row the Admin or Accountant gives the hours to pay (at most the hours per day); payroll waits until they are set.'
              : null),
          _section('Fuel', [
            Dropdown<String>(label: 'Fuel', value: _fuel, width: null, items: const [
              DropdownMenuItem(value: 'VendorSupplies', child: Text('Vendor supplies the fuel')),
              DropdownMenuItem(value: 'CompanySuppliesDeducted', child: Text('We supply, deducted from vendor')),
              DropdownMenuItem(value: 'CompanySuppliesFree', child: Text('We supply, free')),
            ], onChanged: (v) => setState(() => _fuel = v ?? _fuel)),
          ]),
          textField(_notes, 'Notes', maxLines: 2),
        ]),
      ),
    );
  }

  Widget _testCard() {
    final r = _result;
    final cur = _contract?.label.contains('(') == true ? _contract!.label.split('(').last.replaceAll(')', '').trim() : '';
    return Card(
      color: const Color(0xFFF7F8FC),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.science_rounded, color: AppColors.gold),
            const SizedBox(width: 8),
            const Expanded(child: Text('Test this price', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            FilledButton.tonalIcon(
              onPressed: _testing ? null : _test,
              icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded),
              label: const Text('Calculate'),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Sample days in hours. Nothing is saved.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          const SizedBox(height: 12),
          for (var i = 0; i < _rows.length; i++) _sampleRow(i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _rows.length >= 31 ? null : () => setState(() => _rows.add(_SampleRow('Working', gross: 9, brk: 1))),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add day'),
            ),
          ),
          const Divider(),
          FormGrid(columns: 4, children: [
            if (_mode == 'Monthly') textField(_testMonth, 'Month (YYYY-MM)'),
            if (_mode == 'Monthly') textField(_holidayDays, 'Official holidays', number: true, decimal: false),
            if (_fuel == 'CompanySuppliesDeducted') textField(_fuelLiters, 'Fuel litres', number: true),
            if (_fuel == 'CompanySuppliesDeducted') textField(_fuelPrice, 'Price / L', number: true),
          ]),
          if (_testError != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(_testError!, style: const TextStyle(color: AppColors.breakdown))),
          if (r != null) ...[
            const SizedBox(height: 14),
            for (final l in r.list('lines'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(l.str('line_type'), style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text('${Fmt.num2(l.dblOrNull('quantity'))} ${l.str('unit')} × ${Fmt.num2(l.dblOrNull('unit_price'))}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: Text(Fmt.num2(l.dblOrNull('amount')), textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w700, color: l.dbl('amount') < 0 ? AppColors.breakdown : AppColors.ink)),
                  ),
                ]),
              ),
            for (final mo in r.list('monthly'))
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                child: Text(
                  '${mo.str('month')}: ${mo.str('working_days')} working days x ${mo.str('hours_per_day')} h = ${mo.dbl('required_hours').toStringAsFixed(2)} h due · '
                  'done ${mo.dbl('billable_hours').toStringAsFixed(2)} h · hourly price ${mo.dbl('hourly_price').toStringAsFixed(3)}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            const Divider(),
            _total('Gross', r.dbl('gross'), cur),
            _total('Deductions', r.dbl('deductions'), cur, color: AppColors.breakdown),
            _total('Net', r.dbl('net'), cur, big: true),
          ],
        ]),
      ),
    );
  }

  Widget _total(String label, double v, String cur, {Color color = AppColors.ink, bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: big ? FontWeight.w800 : FontWeight.w600, fontSize: big ? 16 : 14))),
          Text(Fmt.money(v, cur.isEmpty ? null : cur), style: TextStyle(fontWeight: FontWeight.w800, fontSize: big ? 18 : 14, color: big ? AppColors.navy : color)),
        ]),
      );

  Widget _sampleRow(int i) {
    final s = _rows[i];
    final working = s.status == 'Working';
    final timed = s.status != 'Absent' && s.status != 'Holiday';
    Widget small(TextEditingController c, String label) => SizedBox(
          width: 74,
          child: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: label, isDense: true)),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 24, child: Text('${i + 1}', style: const TextStyle(color: AppColors.muted))),
        Dropdown<String>(label: 'Day', value: s.status, width: 130, items: const [
          DropdownMenuItem(value: 'Working', child: Text('Working')),
          DropdownMenuItem(value: 'Standby', child: Text('Standby')),
          DropdownMenuItem(value: 'Breakdown', child: Text('Breakdown')),
          DropdownMenuItem(value: 'Absent', child: Text('Absent')),
          DropdownMenuItem(value: 'Holiday', child: Text('Holiday')),
        ], onChanged: (v) => setState(() => s.status = v ?? s.status)),
        if (timed) small(s.gross, working ? 'Gross h' : 'Hours'),
        if (working) small(s.brk, 'Break h'),
        if (working) small(s.breakdown, 'Bkdn h'),
        if (working) small(s.standby, 'Stby h'),
        IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.close_rounded, size: 18),
          onPressed: _rows.length <= 1 ? null : () => setState(() => _rows.removeAt(i)),
        ),
      ]),
    );
  }
}
