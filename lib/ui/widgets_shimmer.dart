import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class CategoryGroupShimmer extends StatelessWidget {
  const CategoryGroupShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
      highlightColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.18),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        horizontalTitleGap: 24,
        title: Container(
          width: double.infinity,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Container(
            width: 150,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

class ShimmerList extends StatelessWidget {
  final int itemCount;
  const ShimmerList({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      padding: const EdgeInsets.all(8.0),
      itemBuilder: (context, index) => const CategoryGroupShimmer(),
    );
  }
}
