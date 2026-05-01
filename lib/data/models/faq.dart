/// A single FAQ entry as stored in the Firestore `faqs` collection.
///
/// Schema (one document per FAQ):
///   • `question` — string
///   • `answer`   — string
///   • `order`    — int (ascending; lowest renders first)
class Faq {
  const Faq({
    required this.question,
    required this.answer,
    required this.order,
  });

  final String question;
  final String answer;
  final int order;

  factory Faq.fromMap(final Map<String, dynamic> data) => Faq(
        question: (data['question'] as String?) ?? '',
        answer: (data['answer'] as String?) ?? '',
        order: (data['order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'question': question,
        'answer': answer,
        'order': order,
      };
}
