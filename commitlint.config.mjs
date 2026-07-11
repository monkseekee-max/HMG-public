import conventional from '@commitlint/config-conventional';

const containsHan = (value) => /\p{Script=Han}/u.test(value ?? '');

const noHan = (field) => (parsed) => [
  !containsHan(parsed[field]),
  `${field} must not contain Unicode Han script characters`,
];

export default {
  ...conventional,
  plugins: [
    {
      rules: {
        'subject-no-han': noHan('subject'),
        'body-no-han': noHan('body'),
        'footer-no-han': noHan('footer'),
      },
    },
  ],
  rules: {
    ...conventional.rules,
    'subject-no-han': [2, 'always'],
    'body-no-han': [2, 'always'],
    'footer-no-han': [2, 'always'],
  },
};
