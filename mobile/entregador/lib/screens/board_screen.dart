import 'dart:async';

import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../courier_api.dart';
import '../freight.dart';
import 'subscription_screen.dart';

/// Mural de corridas: liga/desliga o recebimento (online) e lista as corridas abertas perto de você.
class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.api,
    required this.profile,
    required this.onProfile,
    required this.onAccepted,
    required this.locate,
    required this.visible,
  });

  final CourierApi api;
  final CourierProfile profile;
  final ValueChanged<CourierProfile> onProfile;
  final VoidCallback onAccepted;
  final Future<GeoPoint?> Function() locate;

  /// Tela à vista e app em primeiro plano: só então o mural se atualiza sozinho.
  final bool visible;

  @override
  State<BoardScreen> createState() => BoardScreenState();
}

class BoardScreenState extends State<BoardScreen> {
  var _key = GlobalKey<PagedListState<CourierJobCard>>();
  GeoPoint? _where;
  Timer? _timer;
  bool _switching = false;
  CourierSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _syncTimer();
    _loadSub();
  }

  @override
  void didUpdateWidget(BoardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      _syncTimer();
      if (widget.visible) refresh();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = widget.visible ? Timer.periodic(const Duration(seconds: 20), (_) => _silentRefresh()) : null;
  }

  Future<void> _silentRefresh() async {
    _where = await widget.locate() ?? _where;
    _key.currentState?.refresh();
  }

  Future<void> _loadSub() async {
    try {
      final s = await widget.api.subscription();
      if (mounted) setState(() => _sub = s);
    } catch (_) {
      // o aviso é só um lembrete; sem rede, some
    }
  }

  void refresh() {
    if (mounted) setState(() => _key = GlobalKey());
    _loadSub();
  }

  Future<void> _toggle(bool online) async {
    setState(() => _switching = true);
    try {
      final where = await widget.locate();
      if (where != null) _where = where;
      widget.onProfile(await widget.api.setOnline(online, where));
      if (online) refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _open(CourierJobCard job) async {
    final accepted = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => JobOfferScreen(api: widget.api, job: job)));
    if (accepted == true) {
      widget.onAccepted();
    }
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final online = widget.profile.online;
    return SafeArea(
      child: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: online ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            Icon(online ? Icons.radar_rounded : Icons.pause_circle_outline_rounded, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(online ? 'Você está online' : 'Você está offline', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text(online ? 'Avisamos quando surgir corrida perto de você.' : 'Ligue para receber avisos de corridas.', style: t.bodySmall),
              ]),
            ),
            Transform.scale(
              scale: 1.2,
              child: Switch(value: online, onChanged: _switching ? null : _toggle),
            ),
          ]),
        ),
        if (_sub != null && !_sub!.subscribed && _sub!.freeLeft <= 1)
          _SubscriptionBanner(
            sub: _sub!,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubscriptionScreen(api: widget.api))).then((_) => _loadSub()),
          ),
        Expanded(
          child: PagedList<CourierJobCard>(
            key: _key,
            load: (page) async {
              _where ??= await widget.locate();
              return widget.api.openJobs(page, _where);
            },
            empty: EmptyState(
              icon: Icons.local_shipping_outlined,
              text: online
                  ? 'Nenhuma corrida aberta perto de você agora. Puxe para atualizar.'
                  : 'Nenhuma corrida aberta na sua região. Ligue o app para ser avisado quando surgir.',
            ),
            itemBuilder: (context, j) => _JobCardTile(job: j, onTap: () => _open(j)),
          ),
        ),
      ]),
    );
  }
}

/// "expira em 23 min" / "expira em instantes".
String expiresIn(DateTime at, {DateTime? now}) {
  final left = at.difference(now ?? DateTime.now());
  if (left.inMinutes < 1) return 'expira em instantes';
  if (left.inMinutes < 60) return 'expira em ${left.inMinutes} min';
  return 'expira em ${left.inHours} h';
}

class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({required this.sub, required this.onTap});

  final CourierSubscription sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.card_giftcard_rounded, color: scheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    sub.freeLeft == 0
                        ? 'Suas entregas grátis acabaram. Assine por ${money(sub.price)}/mês para continuar.'
                        : 'Resta ${sub.freeLeft} entrega grátis. Depois, assinatura de ${money(sub.price)}/mês.',
                    style: TextStyle(color: scheme.onTertiaryContainer)),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
    );
  }
}

class _JobCardTile extends StatelessWidget {
  const _JobCardTile({required this.job, required this.onTap});

  final CourierJobCard job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(job.storeName, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (job.pickupAddress != null) Text(job.pickupAddress!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  if (job.distanceToStoreKm != null) _Chip(Icons.near_me_rounded, 'a ${kmLabel(job.distanceToStoreKm!)} de você'),
                  _Chip(Icons.route_rounded, 'trajeto ${kmLabel(job.tripKm)}'),
                  _Chip(Icons.shopping_bag_outlined, job.itemCount == 1 ? '1 item' : '${job.itemCount} itens'),
                ]),
                const SizedBox(height: 6),
                Text('${freightShort(job.freightPayer)} · ${expiresIn(job.expiresAt)}', style: t.bodySmall?.copyWith(color: scheme.outline)),
              ]),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(job.fee), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary)),
              Text('de frete', style: t.bodySmall),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

/// Detalhe da corrida do mural, com o botão de aceitar. Devolve `true` quando aceitou.
class JobOfferScreen extends StatefulWidget {
  const JobOfferScreen({super.key, required this.api, required this.job});

  final CourierApi api;
  final CourierJobCard job;

  @override
  State<JobOfferScreen> createState() => _JobOfferScreenState();
}

class _JobOfferScreenState extends State<JobOfferScreen> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await widget.api.accept(widget.job.id);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 402 || e.code == 'SUBSCRIPTION_REQUIRED') {
        // acabaram as entregas grátis: leva para a assinatura
        await Navigator.push(context, MaterialPageRoute(builder: (_) => SubscriptionScreen(api: widget.api, message: e.message)));
        if (mounted) Navigator.pop(context, false);
      } else if (e.status == 409) {
        showInfo(context, 'Que pena! Outro entregador pegou essa corrida primeiro.');
        Navigator.pop(context, false);
      } else {
        showError(context, e); // inclui o limite de corridas ao mesmo tempo
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Corrida')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(24)),
          child: Column(children: [
            Text('Frete', style: t.bodyMedium),
            Text(money(j.fee), style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary)),
            Text('por ${kmLabel(j.tripKm)} de trajeto', style: t.bodyMedium),
            const SizedBox(height: 4),
            Text(freightWho(j.freightPayer), textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 16),
        _row(context, Icons.storefront_rounded, 'Retirar em', '${j.storeName}${j.pickupAddress == null ? '' : '\n${j.pickupAddress}'}'),
        if (j.distanceToStoreKm != null) _row(context, Icons.near_me_rounded, 'Até a loja', 'a ${kmLabel(j.distanceToStoreKm!)} de você'),
        _row(context, Icons.shopping_bag_outlined, 'Pedido', j.itemCount == 1 ? '1 item' : '${j.itemCount} itens'),
        _row(context, Icons.timer_outlined, 'Disponível', expiresIn(j.expiresAt)),
        const SizedBox(height: 8),
        Text('O endereço do cliente aparece depois que você aceitar.', style: t.bodySmall),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _accept,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Aceitar corrida'),
        ),
      ]),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ]),
          ),
        ]),
      );
}
